package com.example.giant_agent

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "file_receiver"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
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
}
