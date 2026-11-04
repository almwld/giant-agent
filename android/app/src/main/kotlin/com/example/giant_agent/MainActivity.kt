package com.example.giant_agent

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.app.Activity
import android.provider.OpenableColumns
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform

class MainActivity: FlutterActivity() {
    private val CHANNEL = "file_receiver"
    private val AI_CHANNEL = "giant_agent/llama"
    private val AGENT_EVENTS_CHANNEL = "giant_agent_stream"
    private val AGENT_TOOLS_CHANNEL = "giant_agent/tools"
    @Volatile private var agentEventSink: EventChannel.EventSink? = null
    private val aiExecutor = AgentRuntime.aiExecutor
    private val llamaBridge = AgentRuntime.llamaBridge
    private var pendingModelResult: MethodChannel.Result? = null
    companion object { private const val REQUEST_OPEN_MODEL = 7402 }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NotificationBridge.register(this, flutterEngine)

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
                "listWorkspaceFiles" -> {
                    try {
                        val root = File(filesDir, "agent_workspace").apply { mkdirs() }.canonicalFile
                        val files = root.walkTopDown().filter { it.isFile }.mapNotNull { file ->
                            val canonical = file.canonicalFile
                            if (!canonical.path.startsWith(root.path + File.separator) ||
                                canonical.absolutePath != file.absolutePath) null
                            else canonical.relativeTo(root).invariantSeparatorsPath
                        }.take(300).toList()
                        result.success(mapOf("ok" to true, "files" to files))
                    } catch (t: Throwable) {
                        result.error("WORKSPACE_LIST_FAILED", t.message ?: "Unable to list workspace.", null)
                    }
                }
                "createFile" -> {
                    val relativePath = call.argument<String>("path").orEmpty()
                    val content = call.argument<String>("content").orEmpty()
                    val eventId = "tool_${System.nanoTime()}"
                    emitAgentToolStart(eventId, "create_file", relativePath)
                    try {
                        val created = createAgentFile(relativePath, content)
                        emitAgentFileCreated(created.first, content, eventId)
                        result.success(mapOf("ok" to true, "path" to created.first, "name" to created.second))
                    } catch (t: Throwable) {
                        emitAgentToolError("create_file", t.message ?: "File creation failed", eventId)
                        result.error("CREATE_FILE_FAILED", t.message ?: "File creation failed", null)
                    }
                }
                "writeFile" -> {
                    val relativePath = call.argument<String>("path").orEmpty()
                    val content = call.argument<String>("content").orEmpty()
                    val eventId = "tool_${System.nanoTime()}"
                    emitAgentToolStart(eventId, "write_file", relativePath)
                    try {
                        require(content.toByteArray(Charsets.UTF_8).size <= 1024 * 1024) {
                            "File content exceeds the 1 MB limit."
                        }
                        val file = resolveAgentFile(relativePath)
                        require(file.isFile) { "Only existing workspace files can be edited." }
                        file.writeText(content, Charsets.UTF_8)
                        emitAgentFileUpdated(relativePath, content, eventId)
                        result.success(mapOf("ok" to true, "path" to relativePath))
                    } catch (t: Throwable) {
                        emitAgentToolError("write_file", t.message ?: "File update failed", eventId)
                        result.error("WRITE_FILE_FAILED", t.message ?: "File update failed", null)
                    }
                }
                "readFile" -> {
                    val relativePath = call.argument<String>("path").orEmpty()
                    val eventId = "tool_${System.nanoTime()}"
                    emitAgentToolStart(eventId, "read_file", relativePath)
                    try {
                        val file = resolveAgentFile(relativePath)
                        require(file.isFile && file.canRead()) { "File does not exist or cannot be read." }
                        require(file.length() <= 1024 * 1024) { "File exceeds the 1 MB read limit." }
                        val content = file.readText(Charsets.UTF_8)
                        emitAgentFileRead(relativePath, content, eventId)
                        result.success(mapOf("ok" to true, "path" to relativePath, "content" to content))
                    } catch (t: Throwable) {
                        emitAgentToolError("read_file", t.message ?: "File read failed", eventId)
                        result.error("READ_FILE_FAILED", t.message ?: "File read failed", null)
                    }
                }
                "executePython" -> {
                    val code = call.argument<String>("code").orEmpty()
                    val eventId = "python_${System.nanoTime()}"
                    emitPythonEvent("tool_start", code, null, "running", eventId)
                    aiExecutor.execute {
                        try {
                            if (!Python.isStarted()) Python.start(AndroidPlatform(this))
                            val workspace = File(filesDir, "agent_workspace").apply { mkdirs() }.canonicalPath
                            val pyResult = Python.getInstance().getModule("sandbox")
                                .callAttr("run_code", code, workspace)
                            val status = pyResult.get("status")?.toString() ?: "error"
                            val output = pyResult.get("output")?.toString() ?: ""
                            val error = pyResult.get("error")?.toString() ?: ""
                            val ok = status == "success"
                            emitPythonEvent(if (ok) "tool_output" else "tool_error", code,
                                if (ok) output else error, if (ok) "completed" else "failed", eventId)
                            runOnUiThread {
                                result.success(mapOf("ok" to ok, "output" to output, "error" to error))
                            }
                        } catch (t: Throwable) {
                            val message = t.message ?: "Python runtime failed"
                            emitPythonEvent("tool_error", code, message, "failed", eventId)
                            runOnUiThread { result.success(mapOf("ok" to false, "output" to "", "error" to message)) }
                        }
                    }
                }
                "exportWorkspace" -> {
                    aiExecutor.execute {
                        try {
                            val workspace = File(filesDir, "agent_workspace").apply { mkdirs() }.canonicalFile
                            val exportFile = File(cacheDir, "giant-agent-workspace.zip")
                            var count = 0
                            ZipOutputStream(FileOutputStream(exportFile)).use { zip ->
                                workspace.walkTopDown().filter { it.isFile }.forEach { file ->
                                    val canonical = file.canonicalFile
                                    require(canonical.path.startsWith(workspace.path + File.separator)) {
                                        "Workspace contains a path outside its root."
                                    }
                                    require(canonical.absolutePath == file.absolutePath) {
                                        "Symbolic links are not included in workspace exports."
                                    }
                                    val relative = file.relativeTo(workspace).invariantSeparatorsPath
                                    zip.putNextEntry(ZipEntry(relative))
                                    file.inputStream().use { input -> input.copyTo(zip) }
                                    zip.closeEntry()
                                    count++
                                }
                            }
                            runOnUiThread {
                                result.success(mapOf("ok" to true, "path" to exportFile.absolutePath, "files" to count))
                            }
                        } catch (t: Throwable) {
                            runOnUiThread {
                                result.success(mapOf("ok" to false, "error" to (t.message ?: "Workspace export failed")))
                            }
                        }
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
                    else {
                        if (android.os.Build.VERSION.SDK_INT >= 26) startForegroundService(Intent(this, AgentForegroundService::class.java))
                        else startService(Intent(this, AgentForegroundService::class.java))
                        aiExecutor.execute {
                            val ok = try { llamaBridge.nativeLoadModel(path, threads, null, 1.0f) }
                            catch (t: Throwable) { android.util.Log.e("GiantLLM", "GGUF load failed", t); false }
                            if (!ok) stopService(Intent(this, AgentForegroundService::class.java))
                            runOnUiThread { result.success(ok) }
                        }
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
                            val tokenCallback = object : TokenCallback {
                                override fun onToken(token: String) { emitAgentToken(token) }
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

    private fun emitPythonEvent(type: String, code: String, output: String?, status: String, eventId: String) {
        runOnUiThread {
            agentEventSink?.success(mapOf(
                "id" to eventId,
                "type" to type,
                "tool_name" to "execute_python",
                "title" to if (type == "tool_start") "تشغيل Python" else if (type == "tool_output") "مخرجات Python" else "خطأ Python",
                "content" to code,
                "output" to output,
                "status" to status
            ))
        }
    }

    private fun resolveAgentFile(relativePath: String): File {
        require(relativePath.isNotBlank()) { "File path is required." }
        require(!relativePath.startsWith("/") && !relativePath.startsWith("\\")) { "Absolute paths are not allowed." }
        require(!relativePath.contains("\\") && relativePath.split("/").none { it.isBlank() || it == "." || it == ".." }) {
            "Invalid relative path."
        }
        val allowed = setOf("dart", "md", "txt", "json", "yaml", "yml", "html", "css", "js", "kt", "java", "cpp", "h")
        val name = relativePath.substringAfterLast("/")
        require(name.substringAfterLast(".", "").lowercase() in allowed) { "File extension is not allowed." }
        val root = File(filesDir, "agent_workspace").apply { mkdirs() }.canonicalFile
        val candidate = File(root, relativePath)
        val canonical = candidate.canonicalFile
        require(canonical.path.startsWith(root.path + File.separator)) { "File path escapes the agent workspace." }
        require(canonical.canonicalPath == candidate.absolutePath) { "Symbolic links are not allowed." }
        return canonical
    }

    private fun emitAgentFileUpdated(relativePath: String, content: String, eventId: String) {
        runOnUiThread {
            agentEventSink?.success(mapOf(
                "id" to eventId,
                "type" to "file_updated",
                "tool_name" to "write_file",
                "title" to "File updated",
                "file_name" to relativePath,
                "content" to content,
                "status" to "completed"
            ))
        }
    }

    private fun emitAgentFileRead(relativePath: String, content: String, eventId: String) {
        runOnUiThread {
            agentEventSink?.success(mapOf(
                "id" to eventId,
                "type" to "file_read",
                "tool_name" to "read_file",
                "title" to "File read",
                "subtitle" to "تمت قراءة الملف من مساحة العمل",
                "file_name" to relativePath,
                "content" to content,
                "status" to "completed"
            ))
        }
    }

    private fun emitAgentFileCreated(relativePath: String, content: String, eventId: String) {
        runOnUiThread {
            agentEventSink?.success(mapOf(
                "id" to eventId,
                "type" to "file_created",
                "tool_name" to "create_file",
                "title" to "File created",
                "subtitle" to "تم إنشاء الملف داخل مساحة العمل الآمنة",
                "file_name" to relativePath,
                "content" to content,
                "status" to "completed"
            ))
        }
    }

    private fun emitAgentToolStart(eventId: String, tool: String, target: String) {
        runOnUiThread {
            agentEventSink?.success(mapOf(
                "id" to eventId,
                "type" to "tool_start",
                "tool_name" to tool,
                "title" to "بدء تنفيذ $tool",
                "subtitle" to target,
                "status" to "running"
            ))
        }
    }

    private fun emitAgentToolError(tool: String, message: String, eventId: String? = null) {
        runOnUiThread {
            agentEventSink?.success(mapOf(
                "id" to eventId ?: "tool_error_${System.currentTimeMillis()}",
                "type" to "tool_error",
                "tool_name" to tool,
                "title" to "تعذر تنفيذ الأداة: $tool",
                "status" to "failed",
                "details" to message
            ))
        }
    }

    private fun createAgentFile(relativePath: String, content: String): Pair<String, String> {
        require(content.toByteArray(Charsets.UTF_8).size <= 1024 * 1024) { "File content exceeds the 1 MB limit." }
        val target = resolveAgentFile(relativePath)
        target.parentFile?.mkdirs()
        val canonical = resolveAgentFile(relativePath)
        require(!canonical.exists()) { "A file with this path already exists." }
        canonical.writeText(content, Charsets.UTF_8)
        return Pair(relativePath, canonical.name)
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
