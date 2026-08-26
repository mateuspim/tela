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
        val result = storage.store(request("nsfw", "sharedGallery"), noVault)

        assertEquals(false, result["success"])
        assertEquals("restricted", errorCodeOf(result))
    }

    @Test
    fun `the two non-indexed tiers accept nsfw`() {
        for (tier in listOf("filesOutsideGallery", "appPrivate")) {
            val result = storage.store(request("nsfw", tier), noVault)

            // They fail for their own reasons here — no SAF tree, no network —
            // but never as `restricted`, which is the purity gate talking.
            assertNotEquals("tier $tier", "restricted", errorCodeOf(result))
        }
    }

    /** Only `nsfw` is gated; sketchy has always been gallery-eligible. */
    @Test
    fun `sketchy is not treated as nsfw by the gallery tier`() {
        val result = storage.store(request("sketchy", "sharedGallery"), noVault)

        assertNotEquals("restricted", errorCodeOf(result))
    }

    @Test
    fun `an unknown purity or tier is refused rather than guessed at`() {
        val badPurity = storage.store(request("explicit", "appPrivate"), noVault)
        val badTier = storage.store(request("sfw", "downloads"), noVault)

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

        val result = storage.store(request("sfw", "appPrivate", id = "../tela"), noVault)

        assertEquals(false, result["success"])
        assertFalse("a file was written outside the tier", escaped.exists())
    }

    /** A source shape no `SourceId` could hold never reaches a path. */
    @Test
    fun `a traversing source cannot write outside the private tier`() {
        val escaped = File(context.filesDir, "tela.jpg")

        val result = storage.store(
            request("sfw", "appPrivate", id = "tela", source = "../"),
            noVault,
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
        storage.store(request("sfw", "appPrivate", id = "406484", source = "konachan"), noVault)

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

        val result = storage.copy(copyRequest(Uri.fromFile(origin)), noVault)

        assertEquals(true, result["success"])
        val landed = File(privateDirectory(), "wallhaven-abc123.png")
        assertTrue("the copy is not where its name says", landed.exists())
        assertEquals("pixels", landed.readText())
        assertEquals(
            listOf("wallhaven-abc123"),
            imagesFrom(storage.listPrivate(noVault)).map { it["ref"] },
        )
    }

    /** A copy leaves its source alone — deleting it is the caller's step. */
    @Test
    fun `copy does not remove the file it read`() {
        val origin = File(context.cacheDir, "origin.jpg").apply {
            writeText("pixels")
        }

        storage.copy(copyRequest(Uri.fromFile(origin)), noVault)

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
            noVault,
        )

        assertEquals(false, result["success"])
        assertEquals("restricted", errorCodeOf(result))
    }

    /** An unreadable source is a failure, not a zero-byte file left behind. */
    @Test
    fun `copy fails safely when the source cannot be read`() {
        val missing = Uri.fromFile(File(context.cacheDir, "not-there.jpg"))

        val result = storage.copy(copyRequest(missing), noVault)

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
            noVault,
        )

        assertEquals(false, result["success"])
        assertFalse("a file was written outside the tier", escaped.exists())
    }

    private fun copyRequest(
        from: Uri,
        id: String = "abc123",
        purity: String = "sfw",
        tier: String = "appPrivate",
        tag: String? = null,
    ) = ImageCopyRequest(
        source = "wallhaven",
        id = id,
        from = from.toString(),
        purity = purity,
        tier = tier,
        tag = tag,
    )

    // --- tags, which are folders -------------------------------------------

    /**
     * The one tier this suite can really write, so it is where the tag folder is
     * pinned. The gallery and SAF equivalents are device-only for the reason
     * [ImageStorageTestCase] gives, and their paths are pinned instead where
     * they are composed, in [TagFolderTest].
     */
    @Test
    fun `a tagged copy lands in the tag's folder, not the tier root`() {
        val origin = File(context.cacheDir, "origin.jpg").apply { writeText("pixels") }

        val result = storage.copy(copyRequest(Uri.fromFile(origin), tag = "anime"), noVault)

        assertEquals(true, result["success"])
        assertTrue(File(privateDirectory("anime"), "wallhaven-abc123.jpg").exists())
        assertFalse(File(privateDirectory(), "wallhaven-abc123.jpg").exists())
    }

    /** The untagged write is the one every caller made before tags existed, and
     *  it must still land exactly where it did. */
    @Test
    fun `an untagged copy still lands in the tier root`() {
        val origin = File(context.cacheDir, "origin.jpg").apply { writeText("pixels") }

        val result = storage.copy(copyRequest(Uri.fromFile(origin)), noVault)

        assertEquals(true, result["success"])
        assertTrue(File(privateDirectory(), "wallhaven-abc123.jpg").exists())
    }

    /** The tag is the other string this side builds a path from, so it earns the
     *  same test the id has: refused, and nothing written outside the tier. */
    @Test
    fun `a traversing tag is refused and writes nothing`() {
        val origin = File(context.cacheDir, "origin.jpg").apply { writeText("pixels") }
        val escaped = File(context.filesDir, "wallhaven-abc123.jpg")

        val result = storage.copy(
            copyRequest(Uri.fromFile(origin), tag = "../.."),
            noVault,
        )

        assertEquals(false, result["success"])
        assertEquals("unavailable", errorCodeOf(result))
        assertFalse("a file was written outside the tier", escaped.exists())
    }

    /**
     * **One wallpaper, one tag.** Downloading something already stored, under a
     * different tag, means "file it there" — not "keep two". The same judgement
     * the gallery and SAF writers already make about re-downloading at all,
     * arriving by a new door: a tag folder is a fresh way to end up with the
     * pile that `wallhaven-abc123 (1).jpg` used to be (owner, 2026-07-19).
     */
    @Test
    fun `a re-download under another tag moves the wallpaper rather than copying it`() {
        val origin = File(context.cacheDir, "origin.jpg").apply { writeText("pixels") }
        storage.copy(copyRequest(Uri.fromFile(origin), tag = "anime"), noVault)

        storage.copy(copyRequest(Uri.fromFile(origin), tag = "minimal"), noVault)

        assertTrue(File(privateDirectory("minimal"), "wallhaven-abc123.jpg").exists())
        assertFalse(
            "the copy under the old tag survived",
            File(privateDirectory("anime"), "wallhaven-abc123.jpg").exists(),
        )
    }

    /** The sweep runs **after** the write, so a download that fails cannot have
     *  relocated a file the user already had. */
    @Test
    fun `a failed re-download leaves the existing tagged copy alone`() {
        val kept = writePrivateImage("wallhaven-abc123.jpg", tag = "anime")

        val result = storage.store(request("sfw", "appPrivate", id = "abc123"), noVault)

        assertEquals(false, result["success"])
        assertTrue("the earlier copy was swept by a write that never landed", kept.exists())
    }

    /** The tag that was really used is reported back, so a caller never records
     *  one the adapter did not honour. */
    @Test
    fun `a successful write answers with the tag it used`() {
        val origin = File(context.cacheDir, "origin.jpg").apply { writeText("pixels") }

        val tagged = storage.copy(copyRequest(Uri.fromFile(origin), tag = "anime"), noVault)
        val untagged = storage.copy(copyRequest(Uri.fromFile(origin), id = "def456"), noVault)

        assertEquals("anime", tagged["tag"])
        assertFalse("an untagged write must not mention a tag", untagged.containsKey("tag"))
    }

    /**
     * A request that breaks the purity rule *and* carries a bad tag reports the
     * purity rule. The invariant's own answer must not be masked by an argument
     * complaint — someone reading `unavailable` would go looking for a typo
     * rather than learning the gallery had refused an explicit image.
     */
    @Test
    fun `the nsfw refusal outranks a bad tag`() {
        val result = storage.store(
            ImageStoreRequest(
                source = "wallhaven",
                id = "abc123",
                imageUrl = unreachableImage,
                purity = "nsfw",
                tier = "sharedGallery",
                tag = "../..",
            ),
            noVault,
        )

        assertEquals("restricted", errorCodeOf(result))
    }
}
