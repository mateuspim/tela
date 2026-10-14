package cc.pym.tela

/**
 * What a files-tier write does about a document already holding its name.
 *
 * Lifted out of [TierWriting] so it can be tested: the SAF write around it
 * needs a real DocumentsProvider and is device-only.
 */
internal enum class ExistingCopyPolicy {
    /** The document already holds these exact bytes; answer it as written. */
    REUSE,

    /** Delete the document and create a fresh one in its place. */
    REPLACE,

    /** Overwrite the document in place. */
    REWRITE;

    companion object {
        /**
         * [REPLACE] for a device-to-device copy whose leftover does not match.
         *
         * Never [REWRITE] there: on the SM-X730's card an in-place `"wt"`
         * rewrite of an offload leftover failed its readback every time, for
         * all 39 files of one move, and a retried move hit the same files
         * again (owner, 2026-10-07). A fresh document is the path every
         * successful offload already took. Deleting the leftover is safe
         * because the original is still on the device until the new copy
         * verifies. A network re-download has no original to fall back on, so
         * it keeps the in-place rewrite and its "a failure leaves your copy"
         * contract.
         */
        fun decide(isLocalCopy: Boolean, matches: Boolean): ExistingCopyPolicy = when {
            matches -> REUSE
            isLocalCopy -> REPLACE
            else -> REWRITE
        }
    }
}
