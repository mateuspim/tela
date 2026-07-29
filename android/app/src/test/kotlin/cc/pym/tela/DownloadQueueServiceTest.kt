package cc.pym.tela

import android.app.NotificationManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * The queue's process anchor: what it posts, and what it refuses to do.
 *
 * The service exists so a batch of downloads survives the user switching away —
 * a backgrounded app draining a hundred originals is an ordinary low-memory-kill
 * candidate. Its whole contract is the notification it puts in the shade and the
 * fact that it drains nothing itself, so that is what these cover.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DownloadQueueServiceTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    private fun serviceUnder(intent: android.content.Intent): DownloadQueueService {
        val service = Robolectric.buildService(DownloadQueueService::class.java, intent)
            .create()
            .get()
        service.onStartCommand(intent, 0, 1)
        return service
    }

    @Test
    fun `goes foreground with the words it was handed`() {
        val service = serviceUnder(
            DownloadQueueService.start(context, "Downloading wallpapers", "7 left"),
        )

        val posted = shadowOf(service).lastForegroundNotification
        assertNotNull("the service must go foreground, or it anchors nothing", posted)
        val extras = posted!!.extras
        assertEquals("Downloading wallpapers", extras.getString("android.title"))
        assertEquals("7 left", extras.getString("android.text"))
    }

    /**
     * Every user-facing string in tela comes from the Dart ARB, so the service
     * composes none of its own — a notification built in Kotlin would be the one
     * surface that stayed English when a locale was added. Missing extras must
     * therefore degrade to empty, never to a hardcoded English default.
     */
    @Test
    fun `composes no text of its own`() {
        val service = serviceUnder(android.content.Intent(context, DownloadQueueService::class.java))

        val extras = shadowOf(service).lastForegroundNotification!!.extras
        assertEquals("", extras.getString("android.title"))
        assertEquals("", extras.getString("android.text"))
    }

    /** Re-posting under one id updates the shade rather than stacking counts. */
    @Test
    fun `an update replaces the notification rather than adding one`() {
        val controller = Robolectric.buildService(
            DownloadQueueService::class.java,
            DownloadQueueService.start(context, "Downloading wallpapers", "7 left"),
        ).create()
        val service = controller.get()
        service.onStartCommand(
            DownloadQueueService.start(context, "Downloading wallpapers", "6 left"),
            0,
            1,
        )
        service.onStartCommand(
            DownloadQueueService.start(context, "Downloading wallpapers", "5 left"),
            0,
            2,
        )

        val manager = context.getSystemService(NotificationManager::class.java)
        assertEquals(1, shadowOf(manager).allNotifications.size)
        assertEquals(
            "5 left",
            shadowOf(service).lastForegroundNotification!!.extras.getString("android.text"),
        )
    }

    /**
     * The stop intent must be answered *before* going foreground. A stop that
     * posted a notification on its way to `stopSelf` would flash an ongoing
     * "downloading" entry for a queue that had just emptied — and `release` is
     * called on a dead service routinely, since Dart cannot know whether one is
     * up.
     */
    @Test
    fun `stopping posts nothing`() {
        val service = serviceUnder(DownloadQueueService.stop(context))

        assertNull(shadowOf(service).lastForegroundNotification)
        assertTrue("a stop intent must end the service", shadowOf(service).isStoppedBySelf)
    }

    /**
     * A swipe out of recents is the gesture the queue exists to survive.
     *
     * It destroys `MainActivity`, but the Flutter engine is cached on the
     * process ([TelaEngine]), so the Dart drain carries on — and the anchor has
     * to carry on with it or the OS reclaims the process mid-batch. This service
     * used to stop itself here, back when the engine went down with the activity
     * and an anchor that survived would have been an ongoing, undismissable
     * "Downloading… 7 left" over a queue that was not moving.
     *
     * The notification must still be honest, and it is: `release` takes it down
     * the moment nothing is owed, from the same Dart the drain runs on.
     */
    @Test
    fun `a swipe out of recents leaves the drain anchored`() {
        val service = serviceUnder(
            DownloadQueueService.start(context, "Downloading wallpapers", "7 left"),
        )

        service.onTaskRemoved(null)

        assertFalse(
            "the queue keeps draining past the task, so the anchor must too",
            shadowOf(service).isStoppedBySelf,
        )
        assertNotNull(
            "the shade must still say what is happening",
            shadowOf(service).lastForegroundNotification,
        )
    }

    /**
     * A restarted service would come back with no Flutter engine, no queue and
     * nothing to anchor — an ongoing notification for work that is not
     * happening. Recovery belongs to `resumeInterrupted` at the next launch.
     */
    @Test
    fun `does not ask to be restarted`() {
        val intent = DownloadQueueService.start(context, "Downloading wallpapers", "7 left")
        val service = Robolectric.buildService(DownloadQueueService::class.java, intent)
            .create()
            .get()

        assertEquals(
            android.app.Service.START_NOT_STICKY,
            service.onStartCommand(intent, 0, 1),
        )
    }
}
