package com.example.giant_agent

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.zion.os.ai.LlamaBridge
import android.app.Activity
import android.provider.OpenableColumns
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity: FlutterActivity() {
    private val CHANNEL = "file_receiver"
    private val AI_CHANNEL = "giant_agent/llama"
    private val aiExecutor = Executors.newSingleThreadExecutor()
    private val llamaBridge = LlamaBridge()
    private var pendingModelResult: MethodChannel.Result? = null
    companion object { private const val REQUEST_OPEN_MODEL = 7402 }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                        val answer = try { llamaBridge.nativeGenerate(prompt, tokens, temp) }
                        catch (t: Throwable) { "ERROR: ${t.message ?: "native inference failed"}" }
                        runOnUiThread { result.success(answer) }
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
