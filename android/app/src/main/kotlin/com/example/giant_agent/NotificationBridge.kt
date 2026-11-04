package com.example.giant_agent

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object NotificationBridge {
    private const val CHANNEL = "giant_agent/notifications"
    private const val NOTIFICATION_CHANNEL = "giant_agent_general"

    fun register(activity: Activity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    val manager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        manager.createNotificationChannel(
                            NotificationChannel(
                                NOTIFICATION_CHANNEL,
                                "Giant Agent",
                                NotificationManager.IMPORTANCE_DEFAULT
                            )
                        )
                    }
                    when (call.method) {
                        "initialize" -> result.success(manager.areNotificationsEnabled())
                        "areNotificationsEnabled" -> result.success(manager.areNotificationsEnabled())
                        "show" -> {
                            if (!manager.areNotificationsEnabled()) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            val id = call.argument<Int>("id") ?: 1
                            val title = call.argument<String>("title") ?: "Giant Agent"
                            val body = call.argument<String>("body") ?: ""
                            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                Notification.Builder(activity, NOTIFICATION_CHANNEL)
                            } else {
                                Notification.Builder(activity)
                            }
                            val notification = builder
                                .setSmallIcon(android.R.drawable.ic_dialog_info)
                                .setContentTitle(title)
                                .setContentText(body)
                                .setAutoCancel(true)
                                .build()
                            manager.notify(id, notification)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: SecurityException) {
                    result.success(false)
                } catch (error: Throwable) {
                    result.error("NOTIFICATION_FAILED", error.message, null)
                }
            }
    }
}
