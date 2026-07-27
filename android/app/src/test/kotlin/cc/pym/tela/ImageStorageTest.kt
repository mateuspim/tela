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

    private fun request(
        purity: String,
        tier: String,
        id: String = "abc123",
        source: String = "wallhaven",
    ) = ImageStoreRequest(
        source = source,
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
     * - The **source prefix**, which is the load-bearing one and does not look
     *   like a guard at all. `../tela` becomes `wallhaven-../tela.jpg`, and
     *   `wallhaven-..` is an ordinary directory name, not a parent reference —
     *   so the traversal is dead before the regex is consulted. Drop the prefix
     *   and the regex alone still holds; drop both and this test fails with a
     *   file written into `filesDir`. It became the *source's* name on
     *   2026-07-26 and is no weaker for it: `VALID_SOURCE` admits no dot.
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
    fun `deletePrivate removes the file for its key`() {
        val file = writePrivateImage("wallhaven-abc123.jpg")

        val result = storage.deletePrivate("wallhaven-abc123")

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
    fun `deletePrivate refuses a traversing key and deletes nothing`() {
        val outside = File(context.filesDir, "tela.db").apply { writeText("database") }

        val result = storage.deletePrivate("../tela.db")

        assertEquals(false, result["success"])
        assertEquals("unavailable", errorCodeOf(result))
        assertTrue("the file outside the tier survived", outside.exists())
    }

    @Test
    fun `deletePrivate reports a key it holds no file for`() {
        writePrivateImage("wallhaven-abc123.jpg")

        val result = storage.deletePrivate("wallhaven-zzz999")

        assertEquals(false, result["success"])
        assertEquals("unavailable", errorCodeOf(result))
    }

    // --- deleteDownload, the hard delete (J) --------------------------------

    /**
     * The app-private branch recovers the key from the file's own name and reuses
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

        assertEquals(
            listOf("wallhaven-newer", "wallhaven-older"),
            images.map { it["ref"] },
        )
    }

    /**
     * Only names tela itself wrote are listed. A stray file in that directory
     * has no `source-id` to hand back, so it is skipped rather than surfaced
     * with a guessed one.
     */
    @Test
    fun `listPrivate skips files tela did not write`() {
        writePrivateImage("wallhaven-abc123.jpg")
        writePrivateImage("notes.txt")
        writePrivateImage("screenshot.jpg")
        writePrivateImage("IMG-20260726.jpg")

        val images = imagesFrom(storage.listPrivate())

        assertEquals(listOf("wallhaven-abc123"), images.map { it["ref"] })
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

    // --- the source in the file name (2026-07-26) ---------------------------

    /**
     * The regression test for the bug this whole change exists for: `fileName`
     * hardcoded a `wallhaven-` prefix, so **every Konachan download was filed
     * under Wallhaven's name** — in all three tiers, and in the app-private one
     * that name is the only record of where the image came from.
     *
     * The store fails (there is no route to the network here), but it fails
     * *after* opening the file, which is the same seam the traversal test above
     * uses to prove where a write did or did not land.
     */
    @Test
    fun `a download is named for the source that issued it`() {
        storage.store(request("sfw", "appPrivate", id = "406484", source = "konachan"), null)

        assertTrue(File(privateDirectory(), "konachan-406484.jpg").exists())
        assertFalse(
            "the Konachan download was filed under Wallhaven's name",
            File(privateDirectory(), "wallhaven-406484.jpg").exists(),
        )
    }

    /** A source shape no `SourceId` could hold never reaches a path. */
    @Test
    fun `a traversing source cannot write outside the private tier`() {
        val escaped = File(context.filesDir, "tela.jpg")

        val result = storage.store(
            request("sfw", "appPrivate", id = "tela", source = "../"),
            null,
        )

        assertEquals(false, result["success"])
        assertFalse("a file was written outside the tier", escaped.exists())
    }

    @Test
    fun `listPrivate reports which source each file came from`() {
        writePrivateImage("konachan-406484.jpg").setLastModified(9_000L)
        writePrivateImage("wallhaven-abc123.jpg").setLastModified(1_000L)

        val images = imagesFrom(storage.listPrivate())

        assertEquals(
            listOf("konachan-406484", "wallhaven-abc123"),
            images.map { it["ref"] },
        )
    }

    /**
     * The migration that isn't one: every file written before names carried a
     * source is Wallhaven's, and already carries `wallhaven` as its prefix — the
     * hardcoded string happened to be right for the only source that had ever
     * shipped. So an accumulated private tier lists unchanged across this
     * upgrade, with no rename pass and no rows to rewrite.
     */
    @Test
    fun `a file written before the source prefix still lists as wallhaven`() {
        writePrivateImage("wallhaven-abc123.jpg")

        val images = imagesFrom(storage.listPrivate())

        assertEquals("wallhaven-abc123", images.single()["ref"])
    }

    /**
     * Why the key is source-qualified rather than the bare id it used to be:
     * `deletePrivate` deletes **every** file its filter matches, so two sources
     * issuing the same number would have deleted each other's image. Konachan
     * and yande.re really do share an id space this way.
     */
    @Test
    fun `deletePrivate does not reach another source's file with the same id`() {
        val konachan = writePrivateImage("konachan-406484.jpg")
        val other = writePrivateImage("yandere-406484.jpg")

        val result = storage.deletePrivate("konachan-406484")

        assertEquals(true, result["success"])
        assertFalse(konachan.exists())
        assertTrue("another source's file with the same id was deleted", other.exists())
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

    // --- copy, the local-source twin of store -------------------------------

    /**
     * Reachable here where [store] is not: both ends are local, so there is no
     * network to stand in for. It is also the path a "move to the private
     * library" takes, and the one that has to name the file correctly or the
     * image silently vanishes from [listPrivate].
     */
    @Test
    fun `copy lands under source-id and is listed back`() {
        val origin = File(context.cacheDir, "origin.png").apply {
            writeText("pixels")
        }

        val result = storage.copy(copyRequest(Uri.fromFile(origin)), null)

        assertEquals(true, result["success"])
        val landed = File(privateDirectory(), "wallhaven-abc123.png")
        assertTrue("the copy is not where its name says", landed.exists())
        assertEquals("pixels", landed.readText())
        assertEquals(
            listOf("wallhaven-abc123"),
            imagesFrom(storage.listPrivate()).map { it["ref"] },
        )
    }

    /** A copy leaves its source alone — deleting it is the caller's step. */
    @Test
    fun `copy does not remove the file it read`() {
        val origin = File(context.cacheDir, "origin.jpg").apply {
            writeText("pixels")
        }

        storage.copy(copyRequest(Uri.fromFile(origin)), null)

        assertTrue("the source was consumed", origin.exists())
    }

    /**
     * The invariant the whole move-out direction rests on.
     *
     * An image leaving the private tier declares `nsfw` because nothing records
     * what that tier holds beyond a file name — so tela cannot prove it is safe
     * for Photos. What makes that safe rather than merely polite is this
     * refusal, in the adapter, where every other NSFW rule lives.
     */
    @Test
    fun `copy refuses an nsfw image aimed at the gallery`() {
        val origin = File(context.cacheDir, "origin.jpg").apply {
            writeText("pixels")
        }

        val result = storage.copy(
            copyRequest(Uri.fromFile(origin), purity = "nsfw", tier = "sharedGallery"),
            null,
        )

        assertEquals(false, result["success"])
        assertEquals("restricted", errorCodeOf(result))
    }

    /** An unreadable source is a failure, not a zero-byte file left behind. */
    @Test
    fun `copy fails safely when the source cannot be read`() {
        val missing = Uri.fromFile(File(context.cacheDir, "not-there.jpg"))

        val result = storage.copy(copyRequest(missing), null)

        assertEquals(false, result["success"])
        assertEquals("downloadFailed", errorCodeOf(result))
    }

    /** The same path guard the store applies; a copy must not weaken it. */
    @Test
    fun `copy refuses a traversing id`() {
        val origin = File(context.cacheDir, "origin.jpg").apply {
            writeText("pixels")
        }
        val escaped = File(context.filesDir, "tela.jpg")

        val result = storage.copy(
            copyRequest(Uri.fromFile(origin), id = "../tela"),
            null,
        )

        assertEquals(false, result["success"])
        assertFalse("a file was written outside the tier", escaped.exists())
    }

    private fun copyRequest(
        from: Uri,
        id: String = "abc123",
        purity: String = "sfw",
        tier: String = "appPrivate",
    ) = ImageCopyRequest(
        source = "wallhaven",
        id = id,
        from = from.toString(),
        purity = purity,
        tier = tier,
    )
}
