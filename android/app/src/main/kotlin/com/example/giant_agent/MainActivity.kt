package com.example.giant_agent

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import com.zion.os.ai.LlamaBridge
import android.app.Activity
import android.provider.OpenableColumns
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity: FlutterActivity() {
    private val CHANNEL = "file_receiver"
    private val AI_CHANNEL = "giant_agent/llama"
    private val AGENT_EVENTS_CHANNEL = "giant_agent_stream"
    private val AGENT_TOOLS_CHANNEL = "giant_agent/tools"
    @Volatile private var agentEventSink: EventChannel.EventSink? = null
    private val aiExecutor = Executors.newSingleThreadExecutor()
    private val llamaBridge = LlamaBridge()
    private var pendingModelResult: MethodChannel.Result? = null
    companion object { private const val REQUEST_OPEN_MODEL = 7402 }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, AGENT_EVENTS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    agentEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    agentEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AGENT_TOOLS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "createFile" -> {
                    val relativePath = call.argument<String>("path").orEmpty()
                    val content = call.argument<String>("content").orEmpty()
                    try {
                        val created = createAgentFile(relativePath, content)
                        emitAgentFileCreated(created.first, content)
                        result.success(mapOf("ok" to true, "path" to created.first, "name" to created.second))
                    } catch (t: Throwable) {
                        emitAgentToolError("create_file", t.message ?: "File creation failed")
                        result.error("CREATE_FILE_FAILED", t.message ?: "File creation failed", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AI_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "discoverModels" -> aiExecutor.execute { runOnUiThread { result.success(discoverModels()) } }
                "pickModel" -> {
                    if (pendingModelResult != null) result.error("BUSY", "A model import is already open.", null)
                    else {
                        pendingModelResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            type = "application/octet-stream"
                            addCategory(Intent.CATEGORY_OPENABLE)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }
                        try { startActivityForResult(intent, REQUEST_OPEN_MODEL) }
                        catch (t: Throwable) { pendingModelResult = null; result.error("PICKER_FAILED", t.message, null) }
                    }
                }
                "loadModel" -> {
                    val path = call.argument<String>("path").orEmpty()
                    val threads = (call.argument<Int>("threads") ?: 2).coerceIn(1, 8)
                    if (path.isBlank() || !File(path).isFile || !File(path).canRead()) result.success(false)
                    else aiExecutor.execute {
                        val ok = try { llamaBridge.nativeLoadModel(path, threads, null, 1.0f) }
                        catch (t: Throwable) { android.util.Log.e("GiantLLM", "GGUF load failed", t); false }
                        runOnUiThread { result.success(ok) }
                    }
                }
                "generate" -> {
                    val prompt = call.argument<String>("prompt").orEmpty()
                    val tokens = (call.argument<Int>("maxTokens") ?: 256).coerceIn(1, 2048)
                    val temp = (call.argument<Double>("temperature") ?: 0.25).toFloat().coerceIn(0.05f, 1.5f)
                    if (prompt.isBlank()) result.success("") else aiExecutor.execute {
                        emitAgentEvent("request", "تم استلام الطلب وتجهيز النموذج المحلي", "completed")
                        emitAgentEvent("inference", "استدلال النموذج المحلي جارٍ", "running")
                        try {
                            val tokenCallback = object {
                                fun onToken(token: String) { emitAgentToken(token) }
                            }
                            val answer = llamaBridge.nativeGenerateStreaming(prompt, tokens, temp, tokenCallback)
                            emitAgentEvent("inference", "اكتمل توليد الإجابة", "completed")
                            runOnUiThread { result.success(answer) }
                        } catch (t: Throwable) {
                            val message = t.message ?: "native inference failed"
                            emitAgentEvent("inference", "تعذر إكمال الاستدلال المحلي", "failed", message)
                            runOnUiThread { result.error("INFERENCE_FAILED", message, null) }
                        }
                    }
                }
                "cancelGeneration" -> result.success(try { llamaBridge.nativeCancelGeneration() } catch (_: Throwable) { false })
                "isLoaded" -> aiExecutor.execute {
                    val loaded = try { llamaBridge.nativeIsLoaded() } catch (_: Throwable) { false }
                    runOnUiThread { result.success(loaded) }
                }
                "freeModel" -> aiExecutor.execute {
                    try { llamaBridge.nativeFreeModel() } catch (_: Throwable) {}
                    runOnUiThread { result.success(null) }
                }
                "version" -> result.success(try { llamaBridge.nativeVersion() } catch (_: Throwable) { "unavailable" })
                else -> result.notImplemented()
            }
        }
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getSharedFile") {
                val sharedFile = getSharedFile()
                result.success(sharedFile)
            } else {
                result.notImplemented()
            }
        }
    }
    
    private fun emitAgentEvent(id: String, title: String, status: String, details: String? = null) {
        runOnUiThread {
            agentEventSink?.success(mapOf(
                "id" to id,
                "type" to "agent_status",
                "title" to title,
                "status" to status,
                "details" to details
            ))
        }
    }

    private fun emitAgentFileCreated(relativePath: String, content: String) {
        runOnUiThread {
            agentEventSink?.success(mapOf(
                "id" to "file_${System.currentTimeMillis()}",
                "type" to "file_created",
                "title" to "File created",
                "subtitle" to "تم إنشاء الملف داخل مساحة العمل الآمنة",
                "file_name" to relativePath,
                "content" to content,
                "status" to "completed"
            ))
        }
    }

    private fun emitAgentToolError(tool: String, message: String) {
        runOnUiThread {
            agentEventSink?.success(mapOf(
                "id" to "tool_error_${System.currentTimeMillis()}",
                "type" to "tool_error",
                "title" to "تعذر تنفيذ الأداة: $tool",
                "status" to "failed",
                "details" to message
            ))
        }
    }

    private fun createAgentFile(relativePath: String, content: String): Pair<String, String> {
        require(relativePath.isNotBlank()) { "File path is required." }
        require(!relativePath.startsWith("/") && !relativePath.startsWith("\\")) { "Absolute paths are not allowed." }
        require(!relativePath.contains("\\") && relativePath.split("/").none { it.isBlank() || it == "." || it == ".." }) {
            "Invalid relative path."
        }
        require(content.toByteArray(Charsets.UTF_8).size <= 1024 * 1024) { "File content exceeds the 1 MB limit." }
        val allowed = setOf("dart", "md", "txt", "json", "yaml", "yml", "html", "css", "js", "kt", "java", "cpp", "h")
        val name = relativePath.substringAfterLast("/")
        require(name.substringAfterLast(".", "").lowercase() in allowed) { "File extension is not allowed." }

        val root = File(filesDir, "agent_workspace").apply { mkdirs() }.canonicalFile
        val target = File(root, relativePath)
        val parent = target.parentFile ?: throw IllegalArgumentException("Invalid parent directory.")
        parent.mkdirs()
        val canonicalParent = parent.canonicalFile
        require(canonicalParent.path == root.path || canonicalParent.path.startsWith(root.path + File.separator)) {
            "File path escapes the agent workspace."
        }
        val canonicalTarget = File(canonicalParent, target.name)
        require(!canonicalTarget.exists()) { "A file with this path already exists." }
        require(canonicalTarget.canonicalPath == canonicalTarget.absolutePath) { "Symbolic links are not allowed." }
        canonicalTarget.writeText(content, Charsets.UTF_8)
        return Pair(root.toPath().relativize(canonicalTarget.toPath()).toString().replace(File.separator, "/"), name)
    }

    private fun emitAgentToken(token: String) {
        runOnUiThread {
            agentEventSink?.success(mapOf("id" to "token", "type" to "stream_token", "text" to token))
        }
    }

    private fun getSharedFile(): String? {
        when (intent?.action) {
            Intent.ACTION_SEND -> {
                if (intent.type?.startsWith("file/") == true || intent.type == "*/*") {
                    val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                    if (uri != null) {
                        return uri.path
                    }
                }
            }
            Intent.ACTION_VIEW -> {
                val uri = intent.data
                if (uri != null) {
                    return uri.path
                }
            }
        }
        return null
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_OPEN_MODEL) return
        val callback = pendingModelResult
        pendingModelResult = null
        if (callback == null) return
        if (resultCode != Activity.RESULT_OK || data?.data == null) { callback.success(null); return }
        val uri = data.data!!
        aiExecutor.execute {
            try {
                try { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Throwable) {}
                val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) it.getString(0) ?: "model.gguf" else "model.gguf"
                } ?: "model.gguf"
                if (!name.lowercase().endsWith(".gguf")) {
                    runOnUiThread { callback.error("INVALID_MODEL", "Only .gguf files are supported.", null) }
                    return@execute
                }
                val dir = File(filesDir, "models").apply { mkdirs() }
                val safeName = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
                val target = File(dir, safeName)
                val temp = File(dir, "$safeName.part")
                contentResolver.openInputStream(uri).use { input ->
                    requireNotNull(input) { "Cannot read selected model." }
                    FileOutputStream(temp).use { output -> input.copyTo(output, 1024 * 1024); output.fd.sync() }
                }
                if (!temp.renameTo(target)) { temp.copyTo(target, overwrite = true); temp.delete() }
                val payload = mapOf("status" to "IMPORTED", "id" to target.absolutePath,
                    "name" to target.name, "path" to target.absolutePath,
                    "sizeBytes" to target.length(), "size" to String.format("%.1f MB", target.length() / 1048576.0))
                runOnUiThread { callback.success(payload) }
            } catch (t: Throwable) {
                runOnUiThread { callback.error("IMPORT_FAILED", t.message, null) }
            }
        }
    }

    private fun discoverModels(): List<Map<String, Any>> {
        val dir = File(filesDir, "models").apply { mkdirs() }
        return dir.listFiles()?.filter { it.isFile && it.extension.equals("gguf", true) }
            ?.map { mapOf("id" to it.absolutePath, "name" to it.name, "path" to it.absolutePath,
                "sizeBytes" to it.length(), "size" to String.format("%.1f MB", it.length() / 1048576.0),
                "type" to "GGUF", "readable" to it.canRead()) } ?: emptyList()
    }

}
