package cc.pym.tela

import android.net.Uri
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Getting at the bytes of a file tela did not just write — [StoredImageReading],
 * through [ImageStorage].
 *
 * `materialise` needs a real MediaStore or SAF document and stays device-only,
 * so what is reachable here is the two ends around it: whether a stored image
 * can still be opened at all, and the throwaway preview it may have produced.
 * The preview path takes a **path string** off a method channel, which is why it
 * carries a guard of its own — a cache-folder containment check, tested here
 * against both a plain outside path and a traversal.
 *
 * See [ImageStorageTestCase] for what this suite can and cannot reach.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class StoredImageReadingTest : ImageStorageTestCase() {
    private fun previewDirectory(): File = File(context.cacheDir, "previews")

    // --- releasePreview, and its own path guard -----------------------------

    @Test
    fun `releasePreview deletes a preview inside the cache folder`() {
        val directory = previewDirectory().apply { mkdirs() }
        val preview = File(directory, "preview-1").apply { writeText("pixels") }

        storage.releasePreview(preview.absolutePath)

        assertFalse(preview.exists())
    }

    @Test
    fun `releasePreview refuses a path outside the cache folder`() {
        val outside = File(context.filesDir, "tela.db").apply { writeText("database") }

        val result = storage.releasePreview(outside.absolutePath)

        // It answers success either way — releasing is best-effort — but the
        // file it was pointed at must still be there.
        assertEquals(true, result["success"])
        assertTrue("the file outside the cache survived", outside.exists())
    }

    @Test
    fun `releasePreview refuses a traversal out of the cache folder`() {
        val outside = File(context.filesDir, "tela.db").apply { writeText("database") }
        previewDirectory().mkdirs()
        val traversal = File(previewDirectory(), "../../files/tela.db").path

        storage.releasePreview(traversal)

        assertTrue("the traversed-to file survived", outside.exists())
    }

    // --- canRead ------------------------------------------------------------

    @Test
    fun `canRead answers true for a file that is there`() {
        val file = writePrivateImage("wallhaven-abc123.jpg")

        val result = storage.canRead(Uri.fromFile(file))

        assertEquals(true, result["success"])
        assertEquals(true, result["readable"])
    }

    /** A wallpaper the user deleted is a state of the world, not an error. */
    @Test
    fun `canRead answers false for a file that is gone, and does not throw`() {
        val file = writePrivateImage("wallhaven-abc123.jpg")
        file.delete()

        val result = storage.canRead(Uri.fromFile(file))

        assertEquals(true, result["success"])
        assertEquals(false, result["readable"])
    }
}
