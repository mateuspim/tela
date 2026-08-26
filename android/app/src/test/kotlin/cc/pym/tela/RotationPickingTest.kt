package cc.pym.tela

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The order auto-rotate walks its candidates in.
 *
 * Pure logic, so no Robolectric: everything that can go wrong about rotation
 * order — running off the end, a list that shrank between runs, a list of one —
 * is decidable without a device.
 */
class RotationPickingTest {
    @Test
    fun `advances one at a time`() {
        assertEquals(1, RotationPicking.next(count = 5, lastIndex = 0))
        assertEquals(2, RotationPicking.next(count = 5, lastIndex = 1))
    }

    @Test
    fun `wraps at the end`() {
        assertEquals(0, RotationPicking.next(count = 3, lastIndex = 2))
    }

    @Test
    fun `starts at the beginning when nothing was shown yet`() {
        assertEquals(0, RotationPicking.next(count = 4, lastIndex = -1))
    }

    @Test
    fun `a stale cursor past the end starts over instead of failing`() {
        // Files get deleted between runs, so the stored cursor can point past
        // the end of a list that shrank. A rotation that stopped rotating
        // because someone deleted a wallpaper would be a silent death.
        assertEquals(0, RotationPicking.next(count = 2, lastIndex = 9))
    }

    @Test
    fun `a single candidate re-applies itself`() {
        // The alternative is doing nothing, which from the outside looks
        // exactly like a broken schedule.
        assertEquals(0, RotationPicking.next(count = 1, lastIndex = 0))
    }

    @Test
    fun `an empty list has nothing to show`() {
        assertEquals(-1, RotationPicking.next(count = 0, lastIndex = 0))
        assertEquals(-1, RotationPicking.next(count = 0, lastIndex = -1))
    }
}
