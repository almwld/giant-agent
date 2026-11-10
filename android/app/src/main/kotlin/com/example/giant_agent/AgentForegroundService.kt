package com.example.giant_agent

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class AgentForegroundService : Service() {
    companion object {
        const val ACTION_RUNTIME = "com.example.giant_agent.RUNTIME"
        const val ACTION_START_TASK = "com.example.giant_agent.START_TASK"
        const val ACTION_UPDATE = "com.example.giant_agent.UPDATE_TASK"
        const val ACTION_STOP = "com.example.giant_agent.STOP_AGENT_SERVICE"
        private const val CHANNEL_ID = "giant_agent_runtime"
        private const val NOTIFICATION_ID = 7403
        private const val EXTRA_TITLE = "task_title"
        private const val EXTRA_BODY = "task_body"
    }

    @Volatile private var title = "Giant Agent"
    @Volatile private var body = "المحرك المحلي جاهز ويعمل في الخلفية"
    @Volatile private var taskActive = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                taskActive = false
                stopForeground(true)
                stopSelfResult(startId)
                return START_NOT_STICKY
            }
            ACTION_START_TASK -> {
                taskActive = true
                title = intent.getStringExtra(EXTRA_TITLE)?.takeIf { it.isNotBlank() }
                    ?: "Giant Agent — مهمة قيد التنفيذ"
                body = intent.getStringExtra(EXTRA_BODY)?.takeIf { it.isNotBlank() }
                    ?: "يواصل الوكيل تنفيذ المهمة في الخلفية"
            }
            ACTION_UPDATE -> {
                taskActive = true
                title = intent.getStringExtra(EXTRA_TITLE)?.takeIf { it.isNotBlank() } ?: title
                body = intent.getStringExtra(EXTRA_BODY)?.takeIf { it.isNotBlank() } ?: body
            }
            ACTION_RUNTIME -> {
                taskActive = false
                title = "Giant Agent"
                body = "محرك النموذج المحلي جاهز"
            }
            null -> {
                // START_STICKY may recreate the service after process death.
                // Never claim that a task resumed; require the durable recovery flow.
                taskActive = false
                title = "Giant Agent — الاستعادة مطلوبة"
                body = "أُعيد تشغيل خدمة الخلفية. افتح التطبيق لمراجعة المهام المتوقفة."
            }
        }
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification())
        return if (taskActive) START_STICKY else START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        val openApp = packageManager.getLaunchIntentForPackage(packageName)?.let { launch ->
            PendingIntent.getActivity(this, 7403, launch,
                PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(openApp)
            .setOngoing(taskActive)
            .setOnlyAlertOnce(true)
            .setCategory(if (taskActive) NotificationCompat.CATEGORY_SERVICE else NotificationCompat.CATEGORY_STATUS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(NotificationChannel(
                CHANNEL_ID, "Giant Agent runtime", NotificationManager.IMPORTANCE_LOW
            ).apply { description = "إشعارات تنفيذ مهام الوكيل المحلي والاستعادة" })
        }
    }
}
