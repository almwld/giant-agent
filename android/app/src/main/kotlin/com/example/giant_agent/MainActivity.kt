package com.example.giant_agent

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
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
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.google.mlkit.vision.label.ImageLabeling
import com.google.mlkit.vision.label.defaults.ImageLabelerOptions

class MainActivity: FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        AgentRuntime.flutterEngine

    // AgentForegroundService keeps this process alive while durable work runs;
    // retaining the engine also retains the one shared Dart ModelService/LlamaService facade.
    override fun shouldDestroyEngineWithHost(): Boolean = false

    private val CHANNEL = "file_receiver"
    private val AI_CHANNEL = "giant_agent/llama"
    private val AGENT_EVENTS_CHANNEL = "giant_agent_stream"
    private val AGENT_TOOLS_CHANNEL = "giant_agent/tools"
    @Volatile private var agentEventSink: EventChannel.EventSink? = null
    private val pendingSharedFiles = java.util.concurrent.ConcurrentLinkedQueue<String>()
    private val aiExecutor = AgentRuntime.aiExecutor
    private val llamaBridge = AgentRuntime.llamaBridge
    private var pendingModelResult: MethodChannel.Result? = null
    companion object { private const val REQUEST_OPEN_MODEL = 7402 }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        AgentRuntime.retainFlutterEngine(flutterEngine)
        super.configureFlutterEngine(flutterEngine)
        NotificationBridge.register(this, flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "giant_agent/background")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "startTask" -> {
                            dispatchBackgroundService(
                                AgentForegroundService.ACTION_START_TASK,
                                call.argument<String>("title"),
                                call.argument<String>("body")
                            )
                            result.success(true)
                        }
                        "updateTask" -> {
                            AgentForegroundService.updateNotification(
                                applicationContext,
                                call.argument<String>("title") ?: "Giant Agent",
                                call.argument<String>("body") ?: "يواصل الوكيل تنفيذ المهمة في الخلفية"
                            )
                            result.success(true)
                        }
                        "runtimeReady" -> {
                            dispatchBackgroundService(AgentForegroundService.ACTION_RUNTIME, null, null)
                            result.success(true)
                        }
                        "stop" -> {
                            applicationContext.stopService(Intent(applicationContext, AgentForegroundService::class.java))
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Throwable) {
                    result.error("BACKGROUND_SERVICE_FAILED", error.message, null)
                }
            }
        GainPtyBridge.register(this, flutterEngine.dartExecutor.binaryMessenger)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, AGENT_EVENTS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    agentEventSink = events
                    while (true) {
                        val path = pendingSharedFiles.poll() ?: break
                        events?.success(mapOf("id" to "shared_${System.nanoTime()}", "type" to "shared_file", "path" to path))
                    }
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
                        val file = resolveAgentFile(relativePath, textWorkspaceExtensions)
                        require(file.isFile) { "Only existing text/code workspace files can be edited." }
                        file.writeText(content, Charsets.UTF_8)
                        emitAgentFileUpdated(relativePath, content, eventId)
                        result.success(mapOf("ok" to true, "path" to relativePath))
                    } catch (t: Throwable) {
                        emitAgentToolError("write_file", t.message ?: "File update failed", eventId)
                        result.error("WRITE_FILE_FAILED", t.message ?: "File update failed", null)
                    }
                }
                "inspectWorkspaceFile" -> {
                    try {
                        val relativePath = call.argument<String>("path").orEmpty()
                        val file = resolveAgentFile(relativePath)
                        require(file.isFile && file.canRead()) { "Workspace file does not exist or cannot be read." }
                        result.success(mapOf(
                            "ok" to true,
                            "path" to relativePath,
                            "size_bytes" to file.length(),
                            "extension" to file.extension.lowercase()
                        ))
                    } catch (t: Throwable) {
                        result.error("WORKSPACE_FILE_INSPECT_FAILED", t.message ?: "Unable to inspect workspace file.", null)
                    }
                }
                "readFile" -> {
                    val relativePath = call.argument<String>("path").orEmpty()
                    val eventId = "tool_${System.nanoTime()}"
                    emitAgentToolStart(eventId, "read_file", relativePath)
                    try {
                        val file = resolveAgentFile(relativePath, textWorkspaceExtensions)
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
                "recognizeText" -> {
                    val imagePath = call.argument<String>("path").orEmpty()
                    try {
                        val imageFile = File(imagePath)
                        require(imageFile.isFile && imageFile.length() in 1..(12L * 1024L * 1024L)) {
                            "Image must exist and be no larger than 12 MB."
                        }
                        val input = InputImage.fromFilePath(this, Uri.fromFile(imageFile))
                        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                        val labeler = ImageLabeling.getClient(ImageLabelerOptions.DEFAULT_OPTIONS)
                        val ocrTask = recognizer.process(input)
                        val labelTask = labeler.process(input)

                        // Run OCR and visual labeling independently. A failure in one engine
                        // must not discard useful output from the other engine.
                        com.google.android.gms.tasks.Tasks.whenAllComplete(ocrTask, labelTask)
                            .addOnCompleteListener {
                                try {
                                    val payload = mutableMapOf<String, Any>(
                                        "ok" to true,
                                        "text" to "",
                                        "blocks" to 0,
                                        "lines" to emptyList<Map<String, Any>>(),
                                        "labels" to emptyList<Map<String, Any>>(),
                                        "engines" to listOf(
                                            "Google ML Kit Text Recognition (Latin script)",
                                            "Google ML Kit Image Labeling (bundled offline model)"
                                        )
                                    )
                                    if (ocrTask.isSuccessful) {
                                        val visionText = ocrTask.result
                                        payload["text"] = visionText.text
                                        payload["blocks"] = visionText.textBlocks.size
                                        payload["lines"] = visionText.textBlocks.flatMap { block ->
                                            block.lines.map { line ->
                                                val box = line.boundingBox
                                                mapOf(
                                                    "text" to line.text,
                                                    "confidence" to line.confidence,
                                                    "left" to (box?.left ?: 0),
                                                    "top" to (box?.top ?: 0),
                                                    "width" to (box?.width() ?: 0),
                                                    "height" to (box?.height() ?: 0)
                                                )
                                            }
                                        }
                                    } else {
                                        payload["ocr_warning"] = ocrTask.exception?.message ?: "OCR failed"
                                    }
                                    if (labelTask.isSuccessful) {
                                        payload["labels"] = labelTask.result.map { label ->
                                            mapOf(
                                                "text" to label.text,
                                                "confidence" to label.confidence,
                                                "index" to label.index
                                            )
                                        }
                                    } else {
                                        payload["labeling_warning"] = labelTask.exception?.message
                                            ?: "Image labeling unavailable"
                                    }
                                    runOnUiThread { result.success(payload) }
                                } finally {
                                    recognizer.close()
                                    labeler.close()
                                }
                            }
                    } catch (t: Throwable) {
                        result.success(mapOf("ok" to false, "error" to (t.message ?: "Unable to read image")))
                    }
                }
                "extractDocument" -> {
                    val documentPath = call.argument<String>("path").orEmpty()
                    aiExecutor.execute {
                        try {
                            require(documentPath.isNotBlank() && File(documentPath).isFile) {
                                "Document path is invalid."
                            }
                            if (!Python.isStarted()) Python.start(AndroidPlatform(this))
                            val parsed = Python.getInstance().getModule("document_parser")
                                .callAttr("extract_document", documentPath)
                            val payload = mapOf(
                                "ok" to true,
                                "text" to (parsed.get("text")?.toString() ?: ""),
                                "characters_extracted" to (parsed.get("characters_extracted")?.toString()?.toIntOrNull() ?: 0),
                                "truncated" to (parsed.get("truncated")?.toString()?.toBoolean() ?: false),
                                "file_size" to (parsed.get("file_size")?.toString()?.toIntOrNull() ?: 0),
                                "format" to (parsed.get("format")?.toString() ?: "")
                            )
                            runOnUiThread { result.success(payload) }
                        } catch (t: Throwable) {
                            val message = t.message ?: "Document extraction failed."
                            runOnUiThread { result.success(mapOf("ok" to false, "error" to message)) }
                        }
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
                "shareWorkspace" -> {
                    aiExecutor.execute {
                        try {
                            val requestedPaths = call.argument<List<String>>("paths").orEmpty().distinct()
                            require(requestedPaths.isNotEmpty() && requestedPaths.size <= 100) {
                                "Select between 1 and 100 generated files to share."
                            }
                            val workspace = File(filesDir, "agent_workspace").apply { mkdirs() }.canonicalFile
                            val exportFile = File(cacheDir, "giant-agent-task-outputs.zip")
                            var count = 0
                            ZipOutputStream(FileOutputStream(exportFile)).use { zip ->
                                requestedPaths.forEach { relativePath ->
                                    val file = resolveAgentFile(relativePath)
                                    require(file.isFile && file.canRead()) { "Output file is missing: $relativePath" }
                                    val canonical = file.canonicalFile
                                    require(canonical.path.startsWith(workspace.path + File.separator) &&
                                        canonical.absolutePath == file.absolutePath) {
                                        "Output file escapes the workspace or uses a symbolic link."
                                    }
                                    zip.putNextEntry(ZipEntry(canonical.relativeTo(workspace).invariantSeparatorsPath))
                                    file.inputStream().use { input -> input.copyTo(zip) }
                                    zip.closeEntry()
                                    count++
                                }
                            }
                            val uri = FileProvider.getUriForFile(
                                this@MainActivity, "$packageName.fileprovider", exportFile
                            )
                            runOnUiThread {
                                val send = Intent(Intent.ACTION_SEND).apply {
                                    type = "application/zip"
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                startActivity(Intent.createChooser(send, "مشاركة مخرجات المهمة المحددة"))
                                result.success(mapOf("ok" to true, "files" to count))
                            }
                        } catch (t: Throwable) {
                            runOnUiThread { result.error("WORKSPACE_SHARE_FAILED", t.message ?: "Workspace sharing failed.", null) }
                        }
                    }
                }
                "readImagePreview" -> {
                    try {
                        val relativePath = call.argument<String>("path").orEmpty()
                        val file = resolveAgentFile(relativePath)
                        require(file.isFile && file.canRead()) { "Image does not exist or cannot be read." }
                        require(file.extension.lowercase() in setOf("png", "jpg", "jpeg", "webp", "gif", "bmp")) {
                            "Unsupported image format."
                        }
                        require(file.length() in 1..(2L * 1024L * 1024L)) {
                            "Image preview is limited to 2 MB."
                        }
                        val mime = when (file.extension.lowercase()) {
                            "png" -> "image/png"
                            "jpg", "jpeg" -> "image/jpeg"
                            "webp" -> "image/webp"
                            "gif" -> "image/gif"
                            else -> "image/bmp"
                        }
                        val encoded = android.util.Base64.encodeToString(file.readBytes(), android.util.Base64.NO_WRAP)
                        result.success(mapOf("ok" to true, "mime_type" to mime, "base64" to encoded))
                    } catch (t: Throwable) {
                        result.error("IMAGE_PREVIEW_FAILED", t.message ?: "Image preview failed.", null)
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
                        dispatchBackgroundService(AgentForegroundService.ACTION_RUNTIME, null, null)
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
                        // Keep each native inference cycle independently addressable in
                        // the persisted timeline; reusing "request"/"inference" overwrote
                        // earlier cycles in the same conversation.
                        val requestId = "native_${System.nanoTime()}"
                        var terminalStatus = "completed"
                        emitAgentEvent("${requestId}_request", "تم استلام الطلب وتجهيز النموذج المحلي", "pending", requestId = requestId)
                        emitAgentEvent("${requestId}_inference", "استدلال النموذج المحلي جارٍ", "running", requestId = requestId)
                        try {
                            val tokenCallback = object : TokenCallback {
                                override fun onToken(token: String) { emitAgentToken(token, requestId) }
                            }
                            val answer = llamaBridge.nativeGenerateStreaming(prompt, tokens, temp, tokenCallback)
                            terminalStatus = when {
                                answer.startsWith("TIMEOUT:") || answer.startsWith("ERROR:") -> "failed"
                                answer.startsWith("CANCELLED:") || answer.startsWith("تم إيقاف") || answer.contains("[تم إيقاف التوليد]") -> "interrupted"
                                else -> "completed"
                            }
                            val terminalTitle = when (terminalStatus) {
                                "completed" -> "اكتمل توليد الإجابة"
                                "interrupted" -> "تم إيقاف المهمة بواسطة المستخدم"
                                else -> if (answer.startsWith("TIMEOUT:")) "تم إيقاف النموذج بسبب عدم الاستجابة" else "تعذر إكمال الاستدلال المحلي"
                            }
                            emitAgentEvent(
                                "${requestId}_inference",
                                terminalTitle,
                                terminalStatus,
                                if (terminalStatus == "failed") answer else null,
                                requestId
                            )
                            runOnUiThread { result.success(answer) }
                        } catch (t: Throwable) {
                            terminalStatus = "failed"
                            val message = t.message ?: "native inference failed"
                            emitAgentEvent("${requestId}_inference", "تعذر إكمال الاستدلال المحلي", "failed", message, requestId)
                            runOnUiThread { result.error("INFERENCE_FAILED", message, null) }
                        } finally {
                            emitAgentEvent(
                                "${requestId}_finished",
                                if (terminalStatus == "completed") "انتهى تنفيذ الطلب" else if (terminalStatus == "interrupted") "توقف تنفيذ الطلب" else "انتهى الطلب بخطأ",
                                terminalStatus,
                                requestId = requestId,
                                eventType = "task_finished"
                            )
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
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == Intent.ACTION_SEND || intent.action == Intent.ACTION_VIEW) {
            aiExecutor.execute {
                // Capture this exact intent: a later share may replace Activity.intent
                // before this background task reads the content URI.
                val path = getSharedFile(intent) ?: return@execute
                runOnUiThread {
                    val event = mapOf("id" to "shared_${System.nanoTime()}", "type" to "shared_file", "path" to path)
                    val sink = agentEventSink
                    if (sink != null) sink.success(event) else pendingSharedFiles.add(path)
                }
            }
        }
    }

    private fun dispatchBackgroundService(action: String, title: String?, body: String?) {
        val appContext = applicationContext
        val intent = Intent(appContext, AgentForegroundService::class.java).apply {
            this.action = action
            if (!title.isNullOrBlank()) putExtra("task_title", title)
            if (!body.isNullOrBlank()) putExtra("task_body", body)
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            appContext.startForegroundService(intent)
        } else {
            appContext.startService(intent)
        }
    }

    private fun emitAgentEvent(
        id: String,
        title: String,
        status: String,
        details: String? = null,
        requestId: String? = null,
        eventType: String = "agent_status"
    ) {
        runOnUiThread {
            agentEventSink?.success(mapOf(
                // A transition is immutable and gets a fresh ID. The caller's
                // id remains a correlation key for the logical step only.
                "id" to "native_event_${System.nanoTime()}_${java.util.UUID.randomUUID()}",
                "step_id" to id,
                "attempt_id" to requestId,
                "request_id" to requestId,
                "type" to eventType,
                "title" to title,
                "status" to status,
                "details" to details,
                "timestamp" to System.currentTimeMillis()
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

    private val textWorkspaceExtensions = setOf(
        "dart", "md", "txt", "json", "yaml", "yml", "html", "css", "js", "kt", "java",
        "cpp", "h", "c", "cc", "hpp", "ts", "tsx", "jsx", "py", "go", "rs", "sql",
        "sh", "xml", "toml", "gradle", "svg"
    )
    private val workspaceExtensions = textWorkspaceExtensions + setOf(
        "png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "pdf", "doc", "docx",
        "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "zip"
    )

    private fun resolveAgentFile(
        relativePath: String,
        allowedExtensions: Set<String> = workspaceExtensions
    ): File {
        require(relativePath.isNotBlank()) { "File path is required." }
        require(!relativePath.startsWith("/") && !relativePath.startsWith("\\")) { "Absolute paths are not allowed." }
        require(!relativePath.contains("\\") && relativePath.split("/").none { it.isBlank() || it == "." || it == ".." }) {
            "Invalid relative path."
        }
        val name = relativePath.substringAfterLast("/")
        require(name.substringAfterLast(".", "").lowercase() in allowedExtensions) { "File extension is not allowed." }
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
                "id" to (eventId ?: "tool_error_${System.currentTimeMillis()}"),
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
        val target = resolveAgentFile(relativePath, textWorkspaceExtensions)
        target.parentFile?.mkdirs()
        val canonical = resolveAgentFile(relativePath, textWorkspaceExtensions)
        require(!canonical.exists()) { "A file with this path already exists." }
        canonical.writeText(content, Charsets.UTF_8)
        return Pair(relativePath, canonical.name)
    }

    private fun emitAgentToken(token: String, requestId: String) {
        // Each callback carries only the newly decoded UTF-8 chunk from JNI.
        // A unique id lets Dart safely discard a replay without suppressing
        // legitimate adjacent chunks that happen to contain identical text.
        val eventId = "token_${System.nanoTime()}"
        runOnUiThread {
            agentEventSink?.success(mapOf(
                "id" to eventId,
                "request_id" to requestId,
                "attempt_id" to requestId,
                "step_id" to requestId,
                "type" to "stream_token",
                "text" to token,
                "timestamp" to System.currentTimeMillis()
            ))
        }
    }

    private fun getSharedFile(sourceIntent: Intent? = intent): String? {
        val source = when (sourceIntent?.action) {
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                sourceIntent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }
            Intent.ACTION_VIEW -> sourceIntent.data
            else -> null
        } ?: return null

        var partialCopy: File? = null
        return try {
            if (source.scheme == "file") {
                val file = File(source.path ?: return null).canonicalFile
                if (!file.isFile || !file.canRead()) return null
                return file.absolutePath
            }

            require(source.scheme == "content") { "Unsupported shared-file URI scheme." }
            val displayName = contentResolver.query(
                source, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            } ?: "shared_file"
            val safeName = displayName.substringAfterLast('/').substringAfterLast('\\')
                .replace(Regex("[^A-Za-z0-9._-]"), "_").take(100).ifBlank { "shared_file" }
            val destinationDir = File(cacheDir, "shared_files").apply { mkdirs() }.canonicalFile
            val now = System.currentTimeMillis()
            destinationDir.listFiles()?.filter { it.isFile && now - it.lastModified() > 24L * 60 * 60 * 1000 }?.forEach { it.delete() }
            val destination = File(destinationDir, "${System.nanoTime()}_$safeName")
            partialCopy = destination
            val input = contentResolver.openInputStream(source)
                ?: throw java.io.IOException("Unable to open the shared content URI.")
            input.use { stream ->
                FileOutputStream(destination).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        total += count
                        require(total <= 8L * 1024 * 1024) { "Shared file exceeds the 8 MB text-analysis limit." }
                        output.write(buffer, 0, count)
                    }
                    output.fd.sync()
                }
            }
            partialCopy = null
            destination.absolutePath
        } catch (error: Throwable) {
            partialCopy?.delete()
            android.util.Log.e("GiantAgent", "Unable to import shared file", error)
            null
        }
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
