package cc.pym.tela

/**
 * A copy whose readback did not hash to the bytes written into it.
 *
 * Its own type rather than a bare `IllegalStateException` because the write log
 * names only the class that threw — deliberately, see [TierWriteLog] — and an
 * offload of 39 images that all failed as `IllegalStateException` could not
 * say which of five throws it was (owner, 2026-10-07). The byte counts are the
 * rest of the diagnosis and carry no path.
 */
internal class StoredCopyMismatch(
    val expectedBytes: Long,
    val actualBytes: Long?,
    val difference: ByteDifference? = null,
) : IllegalStateException("stored copy did not match its source")
