package cc.pym.tela

import android.graphics.Bitmap
import android.net.Uri
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * [StoredThumbnails]: the persisted grid thumbnail, its collision-safe name,
 * and the rule that it never outlives the file it was made from.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class StoredThumbnailsTest : ImageStorageTestCase() {
    private fun thumbnails() = StoredThumbnails(context)

    private fun writeJpeg(name: String, width: Int, height: Int, tag: String? = null): File {
        val file = writePrivateImage(name, tag = tag)
        file.outputStream().use {
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                .compress(Bitmap.CompressFormat.JPEG, 90, it)
        }
        return file
    }

    private fun cachedFiles(): List<File> =
        TelaDirectories.thumbnails(context).listFiles()?.toList() ?: emptyList()

    /**
     * Robolectric's shadow bitmaps do not decode real pixels, so what is pinned
     * here is the plumbing — descriptor opened, file written under the thumbnail
     * folder — and the real downsampling stays a device check.
     */
    @Test
    fun `a file tile gets a thumbnail file under the thumbnail folder`() {
        val source = writeJpeg("wallhaven-abc123.jpg", 800, 400)

        val result = thumbnails().make(Uri.fromFile(source), 100)

        assertEquals(true, result["success"])
        val path = File(result["path"] as String)
        assertTrue(path.isFile)
        assertEquals(TelaDirectories.thumbnails(context).canonicalPath, path.parentFile!!.canonicalPath)
        assertEquals(listOf(path.name), cachedFiles().map { it.name })
    }

    @Test
    fun `the second request is served from the cache without the source`() {
        val source = writeJpeg("wallhaven-abc123.jpg", 800, 400)
        val first = thumbnails().make(Uri.fromFile(source), 100)
        source.delete()

        val second = thumbnails().make(Uri.fromFile(source), 100)

        assertEquals(true, second["success"])
        assertEquals(first["path"], second["path"])
    }

    @Test
    fun `an unreadable source answers failure and leaves no partial file`() {
        val missing = File(privateDirectory(), "wallhaven-gone00.jpg")

        val result = thumbnails().make(Uri.fromFile(missing), 100)

        assertEquals(false, result["success"])
        assertTrue(cachedFiles().isEmpty())
    }

    /** Regression: the name was `hashCode()`, and "Aa" and "BB" collide on it. */
    @Test
    fun `locations with the same hashCode get different cache files`() {
        val one = Uri.parse("content://x/Aa")
        val two = Uri.parse("content://x/BB")
        assertEquals(one.toString().hashCode(), two.toString().hashCode())

        assertNotEquals(
            StoredThumbnails.cacheName(one, 100),
            StoredThumbnails.cacheName(two, 100),
        )
    }

    @Test
    fun `forget removes every size cached for a location and no other`() {
        val kept = writeJpeg("wallhaven-keep00.jpg", 800, 400)
        val gone = writeJpeg("wallhaven-gone00.jpg", 800, 400)
        thumbnails().make(Uri.fromFile(kept), 100)
        thumbnails().make(Uri.fromFile(gone), 100)
        thumbnails().make(Uri.fromFile(gone), 200)

        thumbnails().forget(Uri.fromFile(gone))

        assertEquals(1, cachedFiles().size)
        assertTrue(cachedFiles().single().name == StoredThumbnails.cacheName(Uri.fromFile(kept), 100))
    }

    @Test
    fun `deleting a private download forgets its thumbnail`() {
        val source = writeJpeg("wallhaven-abc123.jpg", 800, 400)
        thumbnails().make(Uri.fromFile(source), 100)

        storage.deleteDownload("appPrivate", Uri.fromFile(source))

        assertTrue(cachedFiles().isEmpty())
    }

    @Test
    fun `deleting a private image by key forgets its thumbnail`() {
        val source = writeJpeg("wallhaven-abc123.jpg", 800, 400)
        thumbnails().make(Uri.fromFile(source), 100)

        storage.deletePrivate("wallhaven-abc123")

        assertTrue(cachedFiles().isEmpty())
    }

    @Test
    fun `moving a private image to another tag forgets the old thumbnail`() {
        val source = writeJpeg("wallhaven-abc123.jpg", 800, 400)
        thumbnails().make(Uri.fromFile(source), 100)

        val moved = storage.retag("appPrivate", Uri.fromFile(source), "anime", null)

        assertEquals(true, moved["success"])
        assertFalse(cachedFiles().any { it.name.endsWith(".jpg") })
    }
}
