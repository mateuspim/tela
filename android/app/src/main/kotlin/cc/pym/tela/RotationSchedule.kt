package cc.pym.tela

import android.content.Context
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Starts, stops and describes the auto-rotate schedule.
 *
 * WorkManager rather than an `AlarmManager` loop, as PLAN.md names: it survives
 * reboots and doze without either being re-implemented by hand, and it owns the
 * retry backoff the worker leans on when a card is out or a grant is revoked.
 *
 * The schedule is *unique* and replaced rather than added to — two schedules
 * would fight over one screen, and the user only ever expressed one.
 */
internal object RotationSchedule {
    /**
     * Rotates every [intervalMinutes] from [tier] onto [target].
     *
     * WorkManager's own floor is fifteen minutes; a shorter request is silently
     * rounded up rather than refused, which is why the Dart side offers no
     * interval below it — a setting that says five and means fifteen is a lie.
     */
    fun start(
        context: Context,
        intervalMinutes: Long,
        tier: String,
        target: String,
    ) {
        val request = PeriodicWorkRequestBuilder<WallpaperRotationWorker>(
            intervalMinutes,
            TimeUnit.MINUTES,
        ).setInputData(
            Data.Builder()
                .putString(WallpaperRotationWorker.KEY_TIER, tier)
                .putString(WallpaperRotationWorker.KEY_TARGET, target)
                // Carried so [current] can report the plan back without a
                // second store to keep in sync with the schedule itself.
                .putLong(WallpaperRotationWorker.KEY_INTERVAL, intervalMinutes)
                .build(),
        ).build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            WallpaperRotationWorker.WORK_NAME,
            // UPDATE rather than KEEP: a changed interval or tier must take
            // effect, and KEEP would silently leave the old schedule running
            // while the switch claimed the new one.
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
        remember(context, intervalMinutes, tier, target)
    }

    /** Stops rotating. Harmless when nothing is scheduled. */
    fun stop(context: Context) {
        WorkManager.getInstance(context)
            .cancelUniqueWork(WallpaperRotationWorker.WORK_NAME)
        preferences(context).edit().clear().apply()
    }

    /**
     * The plan currently scheduled, or null when rotation is off.
     *
     * Read back off the enqueued work rather than out of tela's own settings,
     * so the switch cannot claim a schedule the platform does not have — a
     * restored backup or a cleared database would otherwise leave the two
     * disagreeing with no way to tell which was right.
     */
    fun current(context: Context): Map<String, Any?>? {
        val scheduled = WorkManager.getInstance(context)
            .getWorkInfosForUniqueWork(WallpaperRotationWorker.WORK_NAME)
            .get()
            // A finished periodic work is a contradiction — periodic work does
            // not finish — so anything terminal is a leftover, not a plan.
            .any { !it.state.isFinished && it.state != WorkInfo.State.CANCELLED }
        if (!scheduled) return null
        val stored = preferences(context)
        val interval = stored.getLong(WallpaperRotationWorker.KEY_INTERVAL, 0L)
        val tier = stored.getString(WallpaperRotationWorker.KEY_TIER, null)
        val target = stored.getString(WallpaperRotationWorker.KEY_TARGET, null)
        // Scheduled but undescribable: the two are written together, so this is
        // an app whose data was cleared under a surviving schedule. Cancel it
        // rather than report half a plan — a rotation nobody can see the
        // settings for is worse than none.
        if (interval == 0L || tier == null || target == null) {
            stop(context)
            return null
        }
        return mapOf(
            "intervalMinutes" to interval,
            "tier" to tier,
            "target" to target,
        )
    }

    /**
     * Records what was just scheduled.
     *
     * `WorkInfo` does not hand back a request's input data, so the *existence*
     * of the schedule is read from WorkManager and its *shape* from here. Both
     * are written in one call so they cannot drift, and [current] cancels a
     * schedule it cannot describe rather than reporting half of one.
     */
    private fun remember(
        context: Context,
        intervalMinutes: Long,
        tier: String,
        target: String,
    ) {
        preferences(context).edit()
            .putLong(WallpaperRotationWorker.KEY_INTERVAL, intervalMinutes)
            .putString(WallpaperRotationWorker.KEY_TIER, tier)
            .putString(WallpaperRotationWorker.KEY_TARGET, target)
            .apply()
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    private const val PREFERENCES = "tela-rotation-plan"
}
