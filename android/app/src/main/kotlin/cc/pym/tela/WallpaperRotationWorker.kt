package cc.pym.tela

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * One scheduled wallpaper change, run by the platform with no Dart alive.
 *
 * **Entirely native, and that is the design decision worth not re-litigating.**
 * A rotation lists a directory, picks a file and hands it to `WallpaperManager`
 * — three things the platform can do alone. Starting a Flutter engine every
 * fifteen minutes to reach them would cost the battery this schedule is meant
 * to be cheap about, and would fail whenever the engine could not start.
 *
 * Everything decidable without a device lives in [RotationPicking], which the
 * unit suite covers; this class is the glue that reads the plan, opens the
 * file and advances the cursor.
 */
internal class WallpaperRotationWorker(
    context: Context,
    parameters: WorkerParameters,
) : Worker(context, parameters) {
    override fun doWork(): Result {
        val tier = inputData.getString(KEY_TIER) ?: return Result.failure()
        val target = inputData.getString(KEY_TARGET) ?: return Result.failure()
        // Read now rather than carried in the input data: a schedule made
        // months ago would otherwise be reading whatever vault was granted on
        // the day it was made, and a user who moved theirs since would have a
        // rotation quietly pointed at the old folder.
        return rotate(tier, target, StorageTargetStore.target(applicationContext))
    }

    private fun rotate(tier: String, target: String, vault: OutsideGalleryTarget): Result {
        val candidates = try {
            RotationCandidates.of(applicationContext, tier, vault)
        } catch (_: Exception) {
            // A revoked grant, an ejected card, a MediaStore that would not
            // answer. None of them are permanent, and failing the work would
            // stop the schedule outright — so this is a retry, not a failure.
            return Result.retry()
        }
        val index = RotationPicking.next(candidates.size, cursor())
        // Nothing downloaded to this tier yet. An ordinary state, and success:
        // retrying would just spin until the user downloads something.
        if (index < 0) return Result.success()
        return apply(candidates[index], target, index)
    }

    private fun apply(source: android.net.Uri, target: String, index: Int): Result {
        return try {
            WallpaperSetting.applyUri(applicationContext, target, source)
            saveCursor(index)
            Result.success()
        } catch (_: Exception) {
            // Deliberately not logging the URI: a rotation from the private
            // library would put an explicit file's path in the log, which
            // CLAUDE.md forbids outright.
            Result.retry()
        }
    }

    /** Where the last-shown index lives between runs. */
    private fun preferences() =
        applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    private fun cursor(): Int = preferences().getInt(KEY_CURSOR, -1)

    private fun saveCursor(index: Int) {
        preferences().edit().putInt(KEY_CURSOR, index).apply()
    }

    companion object {
        /** The unique name the schedule is enqueued under. */
        const val WORK_NAME = "tela-wallpaper-rotation"

        const val KEY_TIER = "tier"
        const val KEY_TARGET = "target"
        const val KEY_INTERVAL = "intervalMinutes"

        private const val PREFERENCES = "tela-rotation"
        private const val KEY_CURSOR = "cursor"
    }
}
