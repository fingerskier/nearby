package io.github.fingerskier.nearby

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Process

/** Notification buttons and dismissals, handled without bringing the app to the front. */
class AlertReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_ID, -1)
        when (intent.action) {
            PRESSED -> {
                context.getSystemService(NotificationManager::class.java).cancel(id)
                Events.emit(mapOf("type" to "action", "id" to id, "key" to intent.getStringExtra(EXTRA_KEY)))
            }
            DISMISSED -> Events.emit(mapOf("type" to "dismissed", "id" to id))
            STOP -> if (!Events.emit(mapOf("type" to "quit"))) {
                // Nothing is running to shut down cleanly; just end.
                WatchService.stop(context)
                Process.killProcess(Process.myPid())
            }
        }
    }

    companion object {
        const val PRESSED = "io.github.fingerskier.nearby.PRESSED"
        const val DISMISSED = "io.github.fingerskier.nearby.DISMISSED"
        const val STOP = "io.github.fingerskier.nearby.STOP"
        private const val EXTRA_ID = "id"
        private const val EXTRA_KEY = "key"

        /** The data URI keeps each notification's intents distinct, since extras don't count. */
        fun intent(context: Context, action: String, id: Int, key: String? = null): PendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, AlertReceiver::class.java)
                .setAction(action)
                .setData(Uri.parse("nearby://notification/$id/${key.orEmpty()}"))
                .putExtra(EXTRA_ID, id)
                .putExtra(EXTRA_KEY, key),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
