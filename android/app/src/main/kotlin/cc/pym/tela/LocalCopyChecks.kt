package cc.pym.tela

import android.content.Context
import android.net.Uri

/**
 * The two questions a device-to-device copy asks of the card: did the bytes
 * arrive, and is a document already there the same image.
 *
 * Out of [TierWriting] because both grew diagnosis of their own on 2026-10-07
 * — the byte counts and difference offsets that found Android redacting GPS on
 * readback — and the writer is about routing, not about proving a copy.
 *
 * ```
 * LocalCopyChecks(context).verify(expected, source, written)
 * ```
 */
internal class LocalCopyChecks(private val context: Context) {
    /**
     * Proves a device-to-device copy before its caller is allowed to delete the
     * source. A successfully closed SAF stream is not proof that removable
     * storage retained every byte; an interrupted or unhealthy card can leave
     * a short document without throwing until it is read back.
     *
     * Remote downloads have no local source and keep their existing contract.
     * The offload path does have one, so an existing corrupt vault document is
     * first replaced (see [ExistingCopyPolicy]) and the new one hashed against
     * the internal bytes. The source digest is accumulated while those bytes
     * are already flowing into the card, avoiding a second full internal read.
     * A mismatch turns the copy into a failure and MoveStoredImages
     * consequently leaves that original in place.
     */
    fun verify(expected: StreamDigest?, source: Uri?, written: Uri) {
        if (expected == null) return
        val actual = context.contentResolver.openInputStream(written)?.use(::digestOf)
        if (expected.sameAs(actual)) return
        val difference = source?.let { differenceBetween(it, written) }
        throw StoredCopyMismatch(expected.length, actual?.length, difference)
    }

    /** Reuses a verified destination left by an interrupted offload. */
    fun matches(source: Uri?, existing: Uri): Boolean {
        if (source == null) return false
        val resolver = context.contentResolver
        val expected = resolver.openInputStream(source)?.use(::digestOf) ?: return false
        val actual = resolver.openInputStream(existing)?.use(::digestOf) ?: return false
        return expected.sameAs(actual)
    }

    /** Where [source] and [written] disagree, read afresh; null if unreadable. */
    private fun differenceBetween(source: Uri, written: Uri): ByteDifference? {
        val resolver = context.contentResolver
        return try {
            resolver.openInputStream(source)?.use { left ->
                resolver.openInputStream(written)?.use { right -> ByteDifference.between(left, right) }
            }
        } catch (_: Exception) {
            null
        }
    }
}
