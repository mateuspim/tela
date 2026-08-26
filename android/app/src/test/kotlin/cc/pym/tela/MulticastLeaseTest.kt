package cc.pym.tela

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The lock beam discovery cannot see without.
 *
 * Android drops multicast not addressed to the device, so a missing lock makes
 * discovery yield nothing at all — with no error and no log to notice. The
 * reference counting is what this suite is really for: two overlapping
 * discoveries must not let the first one's release switch multicast off under
 * the second.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class MulticastLeaseTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @After
    fun releaseEverything() {
        // The lease is an object with process-wide state, so a test that left
        // it held would leak into the next one.
        while (MulticastLease.holderCount > 0) MulticastLease.release()
    }

    @Test
    fun `takes the lock for the first holder`() {
        assertTrue(MulticastLease.acquire(context))

        assertTrue(MulticastLease.isHeld)
        assertEquals(1, MulticastLease.holderCount)
    }

    @Test
    fun `a second holder does not take a second lock`() {
        MulticastLease.acquire(context)
        MulticastLease.acquire(context)

        assertEquals(2, MulticastLease.holderCount)
        assertTrue(MulticastLease.isHeld)
    }

    @Test
    fun `stays held until the last holder leaves`() {
        MulticastLease.acquire(context)
        MulticastLease.acquire(context)

        MulticastLease.release()

        // The bug this guards: a chooser reopened while the first discovery is
        // still winding down, whose release would otherwise blind the second.
        assertTrue(MulticastLease.isHeld)

        MulticastLease.release()

        assertFalse(MulticastLease.isHeld)
        assertEquals(0, MulticastLease.holderCount)
    }

    @Test
    fun `releasing with nothing held is harmless`() {
        // A discovery cancelled twice, or a screen disposed after the engine
        // detached. Crashing there would turn a harmless double-cleanup into a
        // crash on a path nobody is watching.
        MulticastLease.release()

        assertFalse(MulticastLease.isHeld)
        assertEquals(0, MulticastLease.holderCount)
    }

    @Test
    fun `can be taken again after being fully released`() {
        MulticastLease.acquire(context)
        MulticastLease.release()

        assertTrue(MulticastLease.acquire(context))
        assertTrue(MulticastLease.isHeld)
    }
}
