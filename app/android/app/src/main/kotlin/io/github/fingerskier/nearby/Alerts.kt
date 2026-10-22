package io.github.fingerskier.nearby

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri

/** Arrival notifications and the ping. */
class Alerts(private val context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)
    private var nextId = FIRST_ID
    private val shown = NewestIds()

    /** Held so the sound isn't cut short when the Ringtone is collected. */
    private var tone: Ringtone? = null

    init {
        createChannels(context)
        // Arrivals from an earlier process: what their buttons would whitelist went with it, and their ids are
        // about to be reused.
        for (notification in manager.activeNotifications) {
            if (notification.id >= FIRST_ID) manager.cancel(notification.id)
        }
    }

    /** Whether arrival notifications can appear: the app's notifications and their channel are both on. */
    fun allowed(): Boolean =
        manager.areNotificationsEnabled() &&
            manager.getNotificationChannel(ARRIVALS)?.importance != NotificationManager.IMPORTANCE_NONE

    /**
     * Posts a notification and returns its id, or null when the user has turned these notifications off. Only
     * the newest 20 stay up; older ones are taken down and reported dismissed.
     */
    fun show(title: String, body: String, actions: Map<String, String>): Int? {
        if (!allowed()) return null
        val id = nextId++
        val builder = Notification.Builder(context, ARRIVALS)
            .setSmallIcon(R.drawable.ic_stat_nearby)
            .setContentTitle(title)
            .setContentText(body.lineSequence().first())
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_STATUS)
            .setAutoCancel(true)
            .setContentIntent(openApp(context))
            .setDeleteIntent(AlertReceiver.intent(context, AlertReceiver.DISMISSED, id))
        for ((key, label) in actions) {
            builder.addAction(Notification.Action.Builder(null, label, AlertReceiver.intent(context, AlertReceiver.PRESSED, id, key)).build())
        }
        manager.notify(id, builder.build())
        for (old in shown.add(id)) {
            manager.cancel(old)
            Events.emit(mapOf("type" to "dismissed", "id" to old))
        }
        return id
    }

    /** Takes down every arrival notification, e.g. when the app quits and nothing is left to act on them. */
    fun cancelAll() {
        for (id in shown.clear()) manager.cancel(id)
    }

    /** Plays the default notification sound; false if there is none. */
    fun ping(): Boolean {
        val uri: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION) ?: return false
        val next = RingtoneManager.getRingtone(context, uri) ?: return false
        next.audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        tone?.stop()
        tone = next
        next.play()
        return true
    }

    companion object {
        /** Arrivals: heads-up, but silent, because the ping is its own setting. */
        const val ARRIVALS = "arrivals"

        /** The watching service's ongoing notification. */
        const val WATCHING = "watching"

        /** Below this are the service's own notification ids. */
        private const val FIRST_ID = 100

        fun createChannels(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(ARRIVALS, "New devices", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "An unlisted device came into range"
                    setSound(null, null)
                    enableVibration(true)
                },
            )
            manager.createNotificationChannel(
                NotificationChannel(WATCHING, "Watching", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Shown while nearby watches for devices in the background"
                    setShowBadge(false)
                },
            )
        }

        fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
