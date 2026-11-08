package com.example.giant_agent

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Process-owned native PTY bridge ported from Zion OS.
 *
 * The bridge deliberately owns only the PTY lifecycle. It does not import
 * Zion's Termux bootstrap, Kali installer, root-access UI, package manager,
 * or app-specific services. Event listener cancellation detaches the sink;
 * it never destroys a live shell session.
 */
class GainPtyBridge private constructor(
    context: Context,
    messenger: BinaryMessenger,
) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val startExecutor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "gain-pty-start").apply { isDaemon = true }
    }

    private external fun nativeSetPaths(filesDir: String)
    private external fun nativePtyAvailable(): Boolean
    private external fun nativeStartPty(rows: Int, cols: Int, shell: String?): Int
    private external fun nativeReadPty(handle: Int): ByteArray?
    private external fun nativeWritePty(handle: Int, data: ByteArray): Int
    private external fun nativeResizePty(handle: Int, rows: Int, cols: Int): Boolean
    private external fun nativeStopPty(handle: Int)

    init {
        System.loadLibrary("gain_pty")
        val runtimeDirectory = File(appContext.filesDir, "gain_terminal")
        if (!runtimeDirectory.exists()) runtimeDirectory.mkdirs()
        nativeSetPaths(runtimeDirectory.absolutePath)
        registerChannels(messenger)
    }

    private fun registerChannels(messenger: BinaryMessenger) {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(nativePtyAvailable())
                "start" -> {
                    val rows = (call.argument<Int>("rows") ?: 24).coerceIn(8, 100)
                    val cols = (call.argument<Int>("cols") ?: 80).coerceIn(20, 240)
                    val shell = call.argument<String>("shell")
                    startExecutor.execute {
                        val handle = try {
                            startTerminal(rows, cols, shell)
                        } catch (error: Throwable) {
                            android.util.Log.e(TAG, "PTY startup failed", error)
                            0
                        }
                        mainHandler.post { result.success(handle) }
                    }
                }
                "write" -> {
                    val handle = call.argument<Int>("handle") ?: 0
                    val input = call.argument<ByteArray>("input") ?: byteArrayOf()
                    result.success(writeTerminal(handle, input))
                }
                "resize" -> {
                    val handle = call.argument<Int>("handle") ?: 0
                    val rows = call.argument<Int>("rows") ?: 24
                    val cols = call.argument<Int>("cols") ?: 80
                    result.success(resizeTerminal(handle, rows, cols))
                }
                "stop" -> {
                    stopTerminal(call.argument<Int>("handle") ?: 0)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENTS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    terminalSink = events
                }

                override fun onCancel(arguments: Any?) {
                    // UI subscription lifecycle is independent from PTY process lifecycle.
                    terminalSink = null
                }
            },
        )
    }

    private fun startTerminal(rows: Int, cols: Int, shell: String?): Int =
        synchronized(terminalLifecycleLock) {
            val runtimeDirectory = File(appContext.filesDir, "gain_terminal")
            if (!runtimeDirectory.exists() && !runtimeDirectory.mkdirs()) return@synchronized 0
            nativeSetPaths(runtimeDirectory.absolutePath)

            if (!nativePtyAvailable()) {
                android.util.Log.e(TAG, "PTY startup aborted: /dev/ptmx is unavailable")
                return@synchronized 0
            }

            val selectedShell = shell?.trim()?.takeIf { it.isNotEmpty() } ?: "/system/bin/sh"
            val handle = nativeStartPty(rows, cols, selectedShell)
            if (handle <= 0) {
                android.util.Log.e(TAG, "nativeStartPty failed for shell=$selectedShell")
                return@synchronized 0
            }

            // Register before start: a short-lived child must not leave a stale reader.
            val reader = Thread({
                try {
                    var idleDelayMs = 8L
                    while (!Thread.currentThread().isInterrupted) {
                        val data = nativeReadPty(handle) ?: break
                        if (data.isEmpty()) {
                            try {
                                Thread.sleep(idleDelayMs)
                            } catch (_: InterruptedException) {
                                break
                            }
                            idleDelayMs = (idleDelayMs * 2L).coerceAtMost(400L)
                            continue
                        }
                        idleDelayMs = 8L
                        val event = mapOf<String, Any?>("sessionId" to handle, "data" to data)
                        mainHandler.post { terminalSink?.success(event) }
                    }
                } catch (error: Throwable) {
                    mainHandler.post {
                        terminalSink?.error(
                            "GAIN_PTY_STREAM",
                            error.message ?: "PTY output stream failed",
                            mapOf("sessionId" to handle),
                        )
                    }
                } finally {
                    mainHandler.post {
                        terminalSink?.success(mapOf("sessionId" to handle, "closed" to true))
                    }
                    terminalReaders.remove(handle, Thread.currentThread())
                }
            }, "gain-native-pty-$handle").apply { isDaemon = true }

            terminalReaders[handle] = reader
            try {
                reader.start()
                handle
            } catch (error: Throwable) {
                terminalReaders.remove(handle, reader)
                try { nativeStopPty(handle) } catch (_: Throwable) {}
                android.util.Log.e(TAG, "Unable to start PTY reader", error)
                0
            }
        }

    private fun writeTerminal(handle: Int, input: ByteArray): Int =
        synchronized(terminalLifecycleLock) {
            if (handle <= 0 || input.isEmpty()) return@synchronized 0
            try {
                nativeWritePty(handle, input).coerceIn(0, input.size)
            } catch (error: Throwable) {
                android.util.Log.w(TAG, "PTY write failed for handle=$handle", error)
                -1
            }
        }

    private fun resizeTerminal(handle: Int, rows: Int, cols: Int): Boolean =
        synchronized(terminalLifecycleLock) {
            if (handle <= 0) return@synchronized false
            try {
                nativeResizePty(handle, rows.coerceIn(8, 100), cols.coerceIn(20, 240))
            } catch (_: Throwable) {
                false
            }
        }

    private fun stopTerminal(handle: Int) {
        if (handle <= 0) return
        synchronized(terminalLifecycleLock) {
            val reader = terminalReaders.remove(handle)
            reader?.interrupt()
            try { nativeStopPty(handle) } catch (error: Throwable) {
                android.util.Log.w(TAG, "PTY stop failed for handle=$handle", error)
            }
            if (reader != null && reader !== Thread.currentThread()) {
                try {
                    reader.join(750)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                }
            }
        }
    }

    companion object {
        private const val TAG = "GainPTY"
        private const val METHOD_CHANNEL = "giant_agent/pty"
        private const val EVENTS_CHANNEL = "giant_agent/pty/events"
        private val terminalReaders = ConcurrentHashMap<Int, Thread>()
        private val terminalLifecycleLock = Any()
        @Volatile private var terminalSink: EventChannel.EventSink? = null
        @Volatile private var instance: GainPtyBridge? = null

        fun register(context: Context, messenger: BinaryMessenger) {
            synchronized(this) {
                // configureFlutterEngine may be called again after engine recreation.
                // Rebind channels while preserving process-owned native sessions.
                instance = GainPtyBridge(context, messenger)
            }
        }
    }
}
