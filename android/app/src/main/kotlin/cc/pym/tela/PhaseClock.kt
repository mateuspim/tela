package cc.pym.tela

import android.os.SystemClock
import android.util.Log
import org.json.JSONObject

/**
 * Wall-clock per phase of one operation, written as a single structured line.
 *
 * Exists because "moving to the SD card hangs" was diagnosed by reading code,
 * and a card's cost is binder round trips, not CPU: nobody can see by looking
 * which phase is slow. One line per operation, `ms` per phase, plus how many
 * SAF listings the operation issued — the number that exposes an N×M sweep.
 *
 * **Names no path, URI or file name** (CLAUDE.md: NSFW paths never reach a
 * log); the phase names are fixed strings chosen by the caller.
 *
 * ```
 * adb logcat -s tela | grep tela.timing
 * val clock = PhaseClock("sdcopy")
 * clock.phase("write") { writeBytes() }
 * clock.finish()
 * ```
 */
internal class PhaseClock(private val operation: String) {
    private val fields = JSONObject()
    private val startedAt = SystemClock.elapsedRealtime()
    private val listingsAtStart = SafListingCount.total

    /** Runs [block], recording its duration under [name] (summed if repeated). */
    fun <T> phase(name: String, block: () -> T): T {
        val began = SystemClock.elapsedRealtime()
        try {
            return block()
        } finally {
            fields.put(name, fields.optLong(name) + SystemClock.elapsedRealtime() - began)
        }
    }

    /** Adds a plain counter such as a row count, under [name]. */
    fun count(name: String, value: Long) {
        fields.put(name, value)
    }

    /** Emits the line. Call from a `finally` so a failed operation is timed too. */
    fun finish() {
        fields.put("totalMs", SystemClock.elapsedRealtime() - startedAt)
        fields.put("listings", SafListingCount.total - listingsAtStart)
        Log.i("tela", "tela.timing $operation $fields")
    }
}

/** How many SAF child listings this process has issued; see [PhaseClock]. */
internal object SafListingCount {
    @Volatile
    var total: Long = 0L
        private set

    @Synchronized
    fun bump() {
        total += 1
    }
}
