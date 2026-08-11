package cc.pym.tela

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
 * Putting an image into a tier — [TierWriting], through [ImageStorage].
 *
 * Two things are defended here and nowhere else: the **NSFW indexing rule** (an
 * explicit image never reaches the gallery tier, in any of the ways in) and the
 * **path guards**, since this is the only side that builds a path out of strings
 * that arrived over a method channel.
 *
 * See [ImageStorageTestCase] for what this suite can and cannot reach.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class TierWritingTest : ImageStorageTestCase() {
    /** No route out to the network: every store here must fail before it reads. */
    private val unreachableImage = "http://127.0.0.1:1/wallpaper.jpg"

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

    // --- the path guards ----------------------------------------------------

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

    // --- the source in the file name (2026-07-26) ---------------------------

    /**
     * The regression test for the bug that change exists for: `fileName`
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

    // --- copy, the local-source twin of store -------------------------------

    /**
     * Reachable here where `store` is not: both ends are local, so there is no
     * network to stand in for. It is also the path a "move to the private
     * library" takes, and the one that has to name the file correctly or the
     * image silently vanishes from `listPrivate`.
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
