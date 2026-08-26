package cc.pym.tela

import android.content.Context
import android.net.wifi.WifiManager

/**
 * Holds the Wi-Fi multicast lock for as long as tela is looking for receivers.
 *
 * **Without this, discovery silently finds nothing and looks like an empty
 * network.** Android's Wi-Fi stack drops multicast and broadcast packets that
 * are not addressed to the device, to save power — so `joinMulticast` succeeds,
 * the socket stays open, and LocalSend's announcements on `224.0.0.167` never
 * arrive. There is no error anywhere to notice; the list is just always empty.
 *
 * Reference-counted rather than a bare flag: two discoveries can overlap (a
 * chooser reopened while the first is still winding down), and the second
 * release must not switch multicast off under the first.
 *
 * The lock costs battery while held, which is why it is scoped to an open
 * chooser rather than acquired for the life of the process.
 *
 * ```
 * MulticastLease.acquire(context)
 * try { discover() } finally { MulticastLease.release() }
 * ```
 */
internal object MulticastLease {
    /** The tag Android attributes the wake cost to in battery stats. */
    private const val TAG = "tela-beam"

    private var lock: WifiManager.MulticastLock? = null
    private var holders = 0

    /** Whether the lock is currently held. Exposed for the unit suite. */
    val isHeld: Boolean
        get() = lock?.isHeld == true

    /** How many callers are currently holding it open. */
    val holderCount: Int
        get() = holders

    /**
     * Takes the lock, or notes one more holder if it is already taken.
     *
     * Answers false when the device has no Wi-Fi service to ask — an emulator
     * image without one, or a device on cellular only. Discovery is expected to
     * find nothing there, and that is not a failure worth raising: the
     * hand-typed address is the path that still works.
     */
    fun acquire(context: Context): Boolean {
        val wifi = context.applicationContext.getSystemService(WifiManager::class.java)
            ?: return false
        if (lock == null) {
            lock = wifi.createMulticastLock(TAG).apply {
                // Reference counting is Android's, and it is *off* here on
                // purpose: this object counts holders itself, so letting the
                // lock count too would mean two tallies that can disagree.
                setReferenceCounted(false)
                acquire()
            }
        }
        holders++
        return true
    }

    /**
     * Notes one holder leaving, releasing only when the last one does.
     *
     * Tolerates a release with nothing held — a discovery cancelled twice, a
     * screen disposed after the engine detached — because throwing there would
     * turn a harmless double-cleanup into a crash on a path nobody is watching.
     */
    fun release() {
        if (holders == 0) return
        holders--
        if (holders > 0) return
        lock?.takeIf { it.isHeld }?.release()
        lock = null
    }
}
