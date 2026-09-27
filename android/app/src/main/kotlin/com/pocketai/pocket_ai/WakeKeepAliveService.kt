package com.pocketai.pocket_ai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Minimal foreground service that keeps the Pocket AI process alive while
 * the wake-word engine is listening.
 *
 * What it does: raises process importance so Android does not kill the app
 * (and its microphone) when it leaves the foreground. It performs no audio
 * processing itself — the wake-word engine runs in the Flutter layer.
 *
 * What it does NOT do: it cannot override lock-screen mic restrictions or
 * OEM battery killers; those are documented honestly in the README.
 */
class WakeKeepAliveService : Service() {

    companion object {
        private const val CHANNEL_ID = "pocket_ai_listening"
        private const val NOTIFICATION_ID = 1
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Pocket AI listening",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val notification: Notification =
            NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("Pocket AI")
                .setContentText("Listening for \u201cPiti\u201d\u2026")
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setOngoing(true)
                .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }
}
