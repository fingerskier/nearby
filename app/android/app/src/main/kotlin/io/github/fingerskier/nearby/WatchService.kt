package io.github.fingerskier.nearby

import android.app.Notification
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder

/**
 * Keeps the process, and with it the Flutter engine and the guard, running while the app is in the background
 * or swiped away. Its ongoing notification says what nearby is doing and has a Stop button.
 */
class WatchService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Alerts.createChannels(this)
        try {
            startForeground(NOTIFICATION_ID, notification(this, text), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            running = true
        } catch (_: RuntimeException) {
            // Android refuses a connected-device service without the Nearby devices permission; the plugin
            // starts it again once that's granted.
            stopSelf()
        }
        // If Android kills the process, a restarted service would have no engine to run.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    companion object {
        private const val NOTIFICATION_ID = 1

        var running = false
            private set

        /** What the notification says; Dart keeps it current. */
        private var text = "Starting…"

        /** False when Android doesn't allow it from the background; the next try from the foreground will. */
        fun start(context: Context): Boolean = try {
            context.startForegroundService(Intent(context, WatchService::class.java))
            true
        } catch (_: RuntimeException) {
            false
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, WatchService::class.java))
        }

        fun update(context: Context, text: String) {
            if (text == this.text) return
            this.text = text
            if (running) context.getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification(context, text))
        }

        private fun notification(context: Context, text: String): Notification =
            Notification.Builder(context, Alerts.WATCHING)
                .setSmallIcon(R.drawable.ic_stat_nearby)
                .setContentTitle("nearby")
                .setContentText(text)
                .setOngoing(true)
                .setShowWhen(false)
                .setContentIntent(Alerts.openApp(context))
                .addAction(Notification.Action.Builder(null, "Stop", AlertReceiver.intent(context, AlertReceiver.STOP, 0)).build())
                .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
                .build()
    }
}
