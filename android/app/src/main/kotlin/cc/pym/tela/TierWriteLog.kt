package cc.pym.tela

import android.util.Log
import org.json.JSONObject

/**
 * Why a write into a storage tier failed, in the one place that knows.
 *
 * [TierWriting.write] swallows every exception into a flat `downloadFailed`,
 * which is right for the caller — a failed copy is an ordinary outcome there,
 * not a crash — and leaves nobody able to say *why*. That gap cost a whole
 * session: an offload of 2479 images read every source file and wrote none,
 * and the device could only show that it had happened, never what threw
 * (owner, 2026-08-25).
 *
 * **Names no path, no file name and no URL.** This runs for NSFW writes too,
 * where the path is the disclosure (CLAUDE.md), and an exception message from
 * SAF routinely carries the document it failed on. The class of the throw and
 * the tier it was thrown in are what identify the fault; the rest is not worth
 * what it would leak.
 *
 * ```
 * adb logcat -s tela | grep tela.write
 * ```
 */
internal object TierWriteLog {
    private const val TAG = "tela"

    /** Records that a write into [tier] at [purity] was refused, naming [code]. */
    fun refusal(tier: String, purity: String, code: String?) {
        val fields = JSONObject()
            .put("tier", tier)
            .put("purity", purity)
            .put("code", code ?: "unknown")
        Log.w(TAG, "tela.write $fields")
    }

    /** Records that a write into [tier] at [purity] failed with [error]. */
    fun failure(tier: String, purity: String, error: Throwable) {
        Log.w(TAG, "tela.write ${describe(tier, purity, error)}")
    }

    private fun describe(tier: String, purity: String, error: Throwable): String {
        val fields = JSONObject()
            .put("tier", tier)
            .put("purity", purity)
            .put("error", error.javaClass.name)
        val cause = error.cause
        if (cause != null) fields.put("cause", cause.javaClass.name)
        return fields.toString()
    }
}
