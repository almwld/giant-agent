package com.example.giant_agent

import com.zion.os.ai.LlamaBridge
import java.util.concurrent.Executors

/** Process-wide native runtime shared by the Activity and its foreground keep-alive service. */
object AgentRuntime {
    val aiExecutor = Executors.newSingleThreadExecutor()
    val llamaBridge = LlamaBridge()
}
