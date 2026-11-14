package com.lexicandy.mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the Flutter process alive while an Agent run is active.
 *
 * A foreground service is required because Android may otherwise freeze or
 * kill a backgrounded app during the model request. The wake lock covers the
 * screen-off case; it is released when the run finishes, fails or is cancelled
 * by the user, and also expires after 15 minutes as a safety net.
 */
class AgentRunService : Service() {
    companion object {
        const val ACTION_START = "com.lexicandy.mobile.action.AGENT_RUN_START"
        const val ACTION_STOP = "com.lexicandy.mobile.action.AGENT_RUN_STOP"
        private const val CHANNEL_ID = "lexicandy_agent_run"
        private const val NOTIFICATION_ID = 7301
        private const val WAKE_LOCK_TIMEOUT_MS = 15 * 60 * 1000L
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.agent_run_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = getString(R.string.agent_run_notification_text)
                setShowBadge(false)
            }
        manager.createNotificationChannel(channel)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            acquireWakeLock()
            return START_NOT_STICKY
        } catch (_: Exception) {
            // The OS can reject a foreground start (for example when the app
            // is already background-restricted). The Dart run continues; it
            // simply loses the process-lifetime guarantee.
            stopSelf()
            return START_NOT_STICKY
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val openApp =
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
        val pendingIntent =
            PendingIntent.getActivity(
                this,
                0,
                openApp,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.launch_icon)
            .setContentTitle(getString(R.string.agent_run_notification_title))
            .setContentText(getString(R.string.agent_run_notification_text))
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setPriority(Notification.PRIORITY_LOW)
            .build()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val power = getSystemService(PowerManager::class.java)
        wakeLock =
            power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "LexiCandy:AgentRun").apply {
                setReferenceCounted(false)
                acquire(WAKE_LOCK_TIMEOUT_MS)
            }
    }

    private fun releaseWakeLock() {
        val lock = wakeLock ?: return
        wakeLock = null
        if (lock.isHeld) lock.release()
    }
}
