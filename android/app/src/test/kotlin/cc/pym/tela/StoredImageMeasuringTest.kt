package cc.pym.tela

import android.net.Uri
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * How big a stored image is and which disk it is on — [StoredImageMeasuring],
 * through [ImageStorage].
 *
 * What is reachable here is the `file:` half, which is the app-private tier: a
 * real file on a real path. The MediaStore and SAF halves need providers
 * Robolectric does not usefully emulate, so the removability rule for a
 * document URI is pinned through [TreeLocation.parse] in
 * [DownloadFolderDescribingTest] instead, and the size columns stay device-only.
 *
 * See [ImageStorageTestCase] for what this suite can and cannot reach.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class StoredImageMeasuringTest : ImageStorageTestCase() {
    @Test
    fun `measure reports the byte length of a private file`() {
        val file = writePrivateImage("wallhaven-abc123.jpg", contents = "0123456789")

        val measured = storage.measure(Uri.fromFile(file))

        assertEquals(10L, measured["bytes"])
    }

    @Test
    fun `measure calls built-in storage not removable`() {
        val file = writePrivateImage("wallhaven-abc123.jpg")

        val measured = storage.measure(Uri.fromFile(file))

        assertEquals(false, measured["removable"])
    }

    /**
     * A row whose file was deleted must not subtract from the tally: the offload
     * screen adds these up into a promise about freed space, and inventing bytes
     * for a file that is gone would overstate it.
     */
    @Test
    fun `measure answers zero for a file that is gone`() {
        val missing = File(privateDirectory(), "wallhaven-gone.jpg")

        val measured = storage.measure(Uri.fromFile(missing))

        assertEquals(0L, measured["bytes"])
        assertEquals(false, measured["removable"])
    }

    @Test
    fun `measure answers zero for a directory rather than its entry size`() {
        val directory = privateDirectory().apply { mkdirs() }

        val measured = storage.measure(Uri.fromFile(directory))

        assertEquals(0L, measured["bytes"])
    }

    /**
     * A URI naming no provider at all is a failure the caller may not see as
     * one — it answers zero, exactly as an unreadable file does.
     */
    @Test
    fun `measure answers zero for an unreachable content uri`() {
        val measured = storage.measure(Uri.parse("content://cc.pym.nowhere/1"))

        assertEquals(0L, measured["bytes"])
        assertEquals(false, measured["removable"])
    }

    @Test
    fun `measure sums back to the file it was given`() {
        val small = writePrivateImage("wallhaven-small.jpg", contents = "ab")
        val large = writePrivateImage("wallhaven-large.jpg", contents = "abcdefgh")

        val total = listOf(small, large).sumOf {
            storage.measure(Uri.fromFile(it))["bytes"] as Long
        }

        assertTrue("the two files add up", total == 10L)
    }
}
