package com.example.giant_agent

import io.flutter.embedding.engine.FlutterEngine
import com.zion.os.ai.LlamaBridge
import java.util.concurrent.Executors

/** Process-wide native runtime shared by the Activity and its foreground keep-alive service. */
object AgentRuntime {
    /** Keeps the single Flutter/Dart agent isolate alive while the foreground service runs. */
    @Volatile var flutterEngine: FlutterEngine? = null
        private set

    @Synchronized fun retainFlutterEngine(engine: FlutterEngine) {
        if (flutterEngine == null) flutterEngine = engine
    }

    val aiExecutor = Executors.newSingleThreadExecutor()
    val llamaBridge = LlamaBridge()
}
