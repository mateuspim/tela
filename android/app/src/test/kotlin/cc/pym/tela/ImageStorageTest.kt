package cc.pym.tela

import android.content.Context
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The first automated coverage the native layer has ever had.
 *
 * Scope is deliberate: everything here is reachable **without** MediaStore or a
 * SAF tree, which Robolectric does not usefully emulate. That still covers the
 * two things worth defending mechanically — the NSFW indexing rule, and the two
 * path guards that keep a method-channel string from becoming an arbitrary-file
 * delete. The MediaStore and SAF write paths remain device-only; see HANDOFF.
 *
 * Pinned to SDK 35 (`compileSdk`), not the app's `targetSdk` 36, because
 * Robolectric only ships framework jars for SDKs it has been released against.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ImageStorageTest {
    private lateinit var context: Context
    private lateinit var storage: ImageStorage

    /** No route out to the network: every store here must fail before it reads. */
    private val unreachableImage = "http://127.0.0.1:1/wallpaper.jpg"

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        storage = ImageStorage(context)
    }

    private fun privateDirectory(): File = File(context.filesDir, "wallpapers")

    private fun previewDirectory(): File = File(context.cacheDir, "previews")

    private fun writePrivateImage(name: String, contents: String = "pixels"): File {
        val directory = privateDirectory()
        directory.mkdirs()
        return File(directory, name).apply { writeText(contents) }
    }

    private fun request(purity: String, tier: String, id: String = "abc123") = ImageStoreRequest(
        id = id,
        imageUrl = unreachableImage,
        purity = purity,
        tier = tier,
    )

    private fun errorCodeOf(result: Map<String, Any>): String? = result["errorCode"] as String?

    // --- the NSFW rule ------------------------------------------------------

    @Test
    fun `nsfw is refused by the shared gallery tier`() {
        val result = storage.store(request("nsfw", "sharedGallery"), null)

        assertEquals(false, result["success"])
        assertEquals("restricted", errorCodeOf(result))
    }

    @Test
    fun `the two non-indexed tiers accept nsfw`() {
        for (tier in listOf("filesOutsideGallery", "appPrivate")) {
            val result = storage.store(request("nsfw", tier), null)

            // They fail for their own reasons here — no SAF tree, no network —
            // but never as `restricted`, which is the purity gate talking.
            assertNotEquals("tier $tier", "restricted", errorCodeOf(result))
        }
    }

    /** Only `nsfw` is gated; sketchy has always been gallery-eligible. */
    @Test
    fun `sketchy is not treated as nsfw by the gallery tier`() {
        val result = storage.store(request("sketchy", "sharedGallery"), null)

        assertNotEquals("restricted", errorCodeOf(result))
    }

    @Test
    fun `an unknown purity or tier is refused rather than guessed at`() {
        val badPurity = storage.store(request("explicit", "appPrivate"), null)
        val badTier = storage.store(request("sfw", "downloads"), null)

        assertEquals("unavailable", errorCodeOf(badPurity))
        assertEquals("unavailable", errorCodeOf(badTier))
    }

    /**
     * The private tier joins the id onto a directory, so this is the one place a
     * traversing id could really escape.
     *
     * **Two guards stand here, and mutation says it takes both to break it** —
     * worth knowing before anyone "simplifies" either:
     *
     * - `require(VALID_ID…)` in `fileName`, the obvious one.
     * - The `wallhaven-` **prefix**, which is the load-bearing one and does not
     *   look like a guard at all. `../tela` becomes `wallhaven-../tela.jpg`, and
     *   `wallhaven-..` is an ordinary directory name, not a parent reference —
     *   so the traversal is dead before the regex is consulted. Drop the prefix
     *   and the regex alone still holds; drop both and this test fails with a
     *   file written into `filesDir`.
     *
     * `../tela` is chosen over a deeper `../../…` on purpose: it lands in
     * `filesDir`, which exists, so the escaping write would really happen. A
     * traversal into a directory that does not exist fails for the wrong reason
     * and would prove nothing.
     */
    @Test
    fun `a traversing id cannot write outside the private tier`() {
        val escaped = File(context.filesDir, "tela.jpg")

        val result = storage.store(request("sfw", "appPrivate", id = "../tela"), null)

        assertEquals(false, result["success"])
        assertFalse("a file was written outside the tier", escaped.exists())
    }

    // --- deletePrivate, and the path guard ----------------------------------

    @Test
    fun `deletePrivate removes the file for its id`() {
        val file = writePrivateImage("wallhaven-abc123.jpg")

        val result = storage.deletePrivate("abc123")

        assertEquals(true, result["success"])
        assertFalse(file.exists())
    }

    /**
     * The id arrives over a method channel, so a traversing one must not reach
     * a file. Note what actually defends this: `deletePrivate` **filters a
     * listing** rather than building a path, so the traversal has nowhere to go
     * even with `VALID_ID` removed — verified by mutation, where this test kept
     * passing. It pins the outcome, which is the claim that matters; the regex
     * is pinned instead by the store path, where a path *is* built from the id.
     */
    @Test
    fun `deletePrivate refuses a traversing id and deletes nothing`() {
        val outside = File(context.filesDir, "tela.db").apply { writeText("database") }

        val result = storage.deletePrivate("../tela.db")

        assertEquals(false, result["success"])
        assertEquals("unavailable", errorCodeOf(result))
        assertTrue("the file outside the tier survived", outside.exists())
    }

    @Test
    fun `deletePrivate reports an id it holds no file for`() {
        writePrivateImage("wallhaven-abc123.jpg")

        val result = storage.deletePrivate("zzz999")

        assertEquals(false, result["success"])
        assertEquals("unavailable", errorCodeOf(result))
    }

    // --- deleteDownload, the hard delete (J) --------------------------------

    /**
     * The app-private branch recovers the id from the file's own name and reuses
     * [ImageStorage.deletePrivate], so its listing-filter guard still stands —
     * the only tier Robolectric can exercise, the other two being MediaStore and
     * SAF (device-only, as elsewhere in this file).
     */
    @Test
    fun `deleteDownload removes an app-private file and reports it deleted`() {
        val file = writePrivateImage("wallhaven-abc123.jpg")

        val result = storage.deleteDownload("appPrivate", Uri.fromFile(file))

        assertEquals(true, result["success"])
        assertEquals(listOf(Uri.fromFile(file).toString()), result["deleted"])
        assertFalse(file.exists())
    }

    /** A location whose name is not one tela wrote yields no id, so nothing is
     *  deleted — the guard against a method-channel path becoming a file delete. */
    @Test
    fun `deleteDownload refuses an app-private location tela did not write`() {
        val outside = File(context.filesDir, "tela.db").apply { writeText("database") }

        val result = storage.deleteDownload("appPrivate", Uri.fromFile(outside))

        assertEquals(false, result["success"])
        assertEquals("unavailable", errorCodeOf(result))
        assertTrue("the file outside the tier survived", outside.exists())
    }

    @Test
    fun `deleteDownload reports an app-private id it holds no file for`() {
        writePrivateImage("wallhaven-abc123.jpg")

        val result = storage.deleteDownload(
            "appPrivate",
            Uri.parse("file:///data/user/0/cc.pym.tela/files/wallpapers/wallhaven-zzz999.jpg"),
        )

        assertEquals(false, result["success"])
        assertEquals("unavailable", errorCodeOf(result))
    }

    @Test
    fun `deleteDownload refuses an unknown tier rather than guessing`() {
        val result = storage.deleteDownload("downloads", Uri.parse("file:///x.jpg"))

        assertEquals(false, result["success"])
        assertEquals("unavailable", errorCodeOf(result))
    }

    // --- listPrivate --------------------------------------------------------

    @Test
    fun `listPrivate answers newest first`() {
        writePrivateImage("wallhaven-older.jpg").setLastModified(1_000L)
        writePrivateImage("wallhaven-newer.png").setLastModified(9_000L)

        val images = imagesFrom(storage.listPrivate())

        assertEquals(listOf("newer", "older"), images.map { it["id"] })
    }

    /**
     * Only names tela itself wrote are listed. A stray file in that directory
     * has no Wallhaven id to hand back, so it is skipped rather than surfaced
     * with a guessed one.
     */
    @Test
    fun `listPrivate skips files tela did not write`() {
        writePrivateImage("wallhaven-abc123.jpg")
        writePrivateImage("notes.txt")
        writePrivateImage("screenshot.jpg")

        val images = imagesFrom(storage.listPrivate())

        assertEquals(listOf("abc123"), images.map { it["id"] })
    }

    @Test
    fun `listPrivate reports each file's size`() {
        writePrivateImage("wallhaven-abc123.jpg", contents = "0123456789")

        val images = imagesFrom(storage.listPrivate())

        assertEquals(10L, images.single()["sizeBytes"])
    }

    /** An empty tier is an ordinary state, not a failure. */
    @Test
    fun `listPrivate succeeds when nothing has been downloaded`() {
        val result = storage.listPrivate()

        assertEquals(true, result["success"])
        assertTrue(imagesFrom(result).isEmpty())
    }

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

    @Suppress("UNCHECKED_CAST")
    private fun imagesFrom(result: Map<String, Any>): List<Map<String, Any>> =
        result["images"] as List<Map<String, Any>>
}
