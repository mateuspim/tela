package cc.pym.tela

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps the process alive, and prioritised, while the download queue drains.
 *
 * **It does not download anything, and that is the design.** The draining rule
 * lives once, in Dart's `DrainDownloadQueue`, over a Drift table — and around
 * each entry sit the tier resolution, the pin, the history withholding and two
 * NSFW invariants that `PLAN.md` requires be enforced in the domain. A second
 * drainer here would have to restate all of it in Kotlin against the same
 * SQLite file, where the two copies could disagree without anything failing.
 * So there is exactly one drainer, and this raises the priority of the process
 * it already runs in. "The service and the Dart worker never both drain" is
 * therefore structural rather than a rule anyone has to keep.
 *
 * What it buys: a backgrounded app draining a hundred originals is an ordinary
 * candidate for low-memory kill, and the user who started that batch and
 * switched away is the exact person it gets killed on. A foreground service
 * makes the process the last thing the OS reclaims, and puts a notification in
 * the shade saying why.
 *
 * **It survives a swipe out of recents**, and that is only honest because the
 * engine does too. The drain is Dart, so an anchor that outlived the engine
 * would be an ongoing, undismissable "Downloading… 7 left" over a queue that is
 * not moving — worse than no anchor at all. [TelaEngine] caches the engine past
 * the activity, so the work the notification describes really is still running;
 * before that, this service stopped itself in `onTaskRemoved`. The manifest's
 * `stopWithTask="false"` is what leaves the choice to us.
 *
 * ```kotlin
 * startService(DownloadQueueService.start(context, "Downloading", "3 left"))
 * ```
 */
class DownloadQueueService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * Answers [START_NOT_STICKY] deliberately: a service the system restarts on
     * its own comes back with a fresh process, no queue loaded and nothing to
     * anchor — a notification for work that is not happening. A killed drain is
     * picked up by `resumeInterrupted` at the next launch, which is where the
     * recovery rule already lives.
     */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra(EXTRA_TITLE).orEmpty()
        val body = intent?.getStringExtra(EXTRA_BODY).orEmpty()
        goForeground(title, body)
        return START_NOT_STICKY
    }

    /**
     * Posts (or re-posts) the ongoing notification.
     *
     * `startForeground` with the same id updates in place, so progress and stop
     * go through one path rather than a start/notify split that could leave the
     * service foreground with a stale count on it.
     */
    private fun goForeground(title: String, body: String) {
        val notification = buildNotification(title, body)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(title: String, body: String): Notification {
        ensureChannel()
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(openApp())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    /**
     * Tapping the notification returns to tela rather than launching a second
     * copy — `singleTop` on the activity plus the default launch intent.
     */
    private fun openApp(): PendingIntent? {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        return PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * `IMPORTANCE_LOW`: the shade entry is a status, not an event. At default
     * importance every queue start would make a sound, and a batch the user
     * themselves just asked for has nothing to announce.
     */
    private fun ensureChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            channelName,
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.setShowBadge(false)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    /**
     * The channel's own name, the one string here Android shows without being
     * handed it — it appears in system notification settings, outside any
     * moment tela could pass text in from Dart's l10n. Read from the app's
     * resources so it is still translatable in the only way Android allows.
     */
    private val channelName: String
        get() = getString(R.string.download_queue_channel_name)

    companion object {
        private const val CHANNEL_ID = "download-queue"
        private const val NOTIFICATION_ID = 1
        private const val ACTION_STOP = "cc.pym.tela.STOP_DOWNLOAD_QUEUE"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_BODY = "body"

        /**
         * The intent that starts the service, or updates its notification.
         *
         * [title] and [body] are passed in rather than built here: every
         * user-facing string in tela comes from the Dart ARB (CLAUDE.md), and a
         * notification composed in Kotlin would be the one screen that quietly
         * stayed English when a locale was added.
         */
        fun start(context: Context, title: String, body: String): Intent {
            return Intent(context, DownloadQueueService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_BODY, body)
        }

        /** The intent that takes the service back down. */
        fun stop(context: Context): Intent {
            return Intent(context, DownloadQueueService::class.java).setAction(ACTION_STOP)
        }

        /**
         * Starts the service or updates its notification. Answers whether the
         * anchor is up.
         *
         * **The failure it swallows is a real one, not defensive noise.** From
         * Android 12, starting a foreground service while the app is already in
         * the background throws `ForegroundServiceStartNotAllowedException` —
         * reachable here whenever a drain begins from something other than a
         * tap, a retry fired by a queue that resumed after the user had already
         * switched away. There is nothing to do about it and nothing to tell
         * the user: the drain still runs, it is merely killable again, which is
         * exactly where it stood before this service existed. Answering false
         * keeps Dart from believing it has an anchor it does not have.
         *
         * Caught as [Exception] rather than by name because the class is API 31
         * and this module compiles against a lower minimum; the OEM variants of
         * this refusal are not one type either.
         */
        fun anchor(context: Context, title: String, body: String): Boolean {
            return try {
                context.startForegroundService(start(context, title, body))
                true
            } catch (_: Exception) {
                false
            }
        }

        /**
         * Takes the anchor down. Safe to call when nothing is running — a stop
         * intent to a dead service starts nothing, since [onStartCommand]
         * answers [ACTION_STOP] with `stopSelf` before going foreground.
         */
        fun release(context: Context) {
            try {
                context.startService(stop(context))
            } catch (_: Exception) {
                // Backgrounded with no service up: there is nothing to take down.
            }
        }
    }
}
