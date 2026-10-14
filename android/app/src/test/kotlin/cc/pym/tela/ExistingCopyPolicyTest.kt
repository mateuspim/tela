package cc.pym.tela

import org.junit.Assert.assertEquals
import org.junit.Test

class ExistingCopyPolicyTest {
    @Test
    fun `a matching document is reused, whatever wrote it`() {
        assertEquals(ExistingCopyPolicy.REUSE, ExistingCopyPolicy.decide(isLocalCopy = true, matches = true))
        assertEquals(ExistingCopyPolicy.REUSE, ExistingCopyPolicy.decide(isLocalCopy = false, matches = true))
    }

    /**
     * Regression: rewriting an offload leftover in place failed its readback
     * for all 39 files of a move, every retry (owner, 2026-10-07).
     */
    @Test
    fun `a mismatched offload leftover is replaced, never rewritten in place`() {
        assertEquals(
            ExistingCopyPolicy.REPLACE,
            ExistingCopyPolicy.decide(isLocalCopy = true, matches = false),
        )
    }

    /** No original to fall back on, so the existing copy must survive a failure. */
    @Test
    fun `a network re-download still rewrites in place`() {
        assertEquals(
            ExistingCopyPolicy.REWRITE,
            ExistingCopyPolicy.decide(isLocalCopy = false, matches = false),
        )
    }
}
