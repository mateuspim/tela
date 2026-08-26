package cc.pym.tela

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Reading back the one tier nothing else can show — [PrivateTierListing],
 * through [ImageStorage].
 *
 * The private library screen has no index behind it: the directory listing *is*
 * the library, and a file's name is the only record of what it is and where it
 * came from. So the rules pinned here are about what a name earns — an
 * unrecognised one is skipped rather than surfaced with a guessed source.
 *
 * See [ImageStorageTestCase] for what this suite can and cannot reach.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PrivateTierListingTest : ImageStorageTestCase() {
    @Test
    fun `listPrivate answers newest first`() {
        writePrivateImage("wallhaven-older.jpg").setLastModified(1_000L)
        writePrivateImage("wallhaven-newer.png").setLastModified(9_000L)

        val images = imagesFrom(storage.listPrivate(noVault))

        assertEquals(
            listOf("wallhaven-newer", "wallhaven-older"),
            images.map { it["ref"] },
        )
    }

    /**
     * The narrower listing exists for its **cost**, not its answer: with no
     * vault in the picture the two must agree exactly, or the offload survey
     * would be tallying a different library than the one on screen.
     */
    @Test
    fun `listAppPrivate answers what listPrivate does with no vault`() {
        writePrivateImage("wallhaven-older.jpg").setLastModified(1_000L)
        writePrivateImage("wallhaven-newer.png").setLastModified(9_000L)
        writePrivateImage("wallhaven-tagged.jpg", tag = "anime")

        assertEquals(
            imagesFrom(storage.listPrivate(noVault)),
            imagesFrom(storage.listAppPrivate()),
        )
    }

    @Test
    fun `listAppPrivate succeeds when nothing has been downloaded`() {
        val result = storage.listAppPrivate()

        assertEquals(true, result["success"])
        assertTrue(imagesFrom(result).isEmpty())
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

        val images = imagesFrom(storage.listPrivate(noVault))

        assertEquals(listOf("wallhaven-abc123"), images.map { it["ref"] })
    }

    @Test
    fun `listPrivate reports each file's size`() {
        writePrivateImage("wallhaven-abc123.jpg", contents = "0123456789")

        val images = imagesFrom(storage.listPrivate(noVault))

        assertEquals(10L, images.single()["sizeBytes"])
    }

    /** An empty tier is an ordinary state, not a failure. */
    @Test
    fun `listPrivate succeeds when nothing has been downloaded`() {
        val result = storage.listPrivate(noVault)

        assertEquals(true, result["success"])
        assertTrue(imagesFrom(result).isEmpty())
    }

    @Test
    fun `listPrivate reports which source each file came from`() {
        writePrivateImage("konachan-406484.jpg").setLastModified(9_000L)
        writePrivateImage("wallhaven-abc123.jpg").setLastModified(1_000L)

        val images = imagesFrom(storage.listPrivate(noVault))

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

        val images = imagesFrom(storage.listPrivate(noVault))

        assertEquals("wallhaven-abc123", images.single()["ref"])
    }

    // --- tags, which are folders -------------------------------------------

    /** A tag is a directory here, so a listing that did not descend would show a
     *  fully tagged library as empty. */
    @Test
    fun `listPrivate finds tagged images and names their tag`() {
        writePrivateImage("wallhaven-abc123.jpg", tag = "anime")

        val image = imagesFrom(storage.listPrivate(noVault)).single()

        assertEquals("wallhaven-abc123", image["ref"])
        assertEquals("anime", image["tag"])
    }

    /** Absent, not null: a row that never mentions a tag reads back the same as
     *  every row written before tags existed. */
    @Test
    fun `an untagged image carries no tag at all`() {
        writePrivateImage("wallhaven-abc123.jpg")

        assertFalse(imagesFrom(storage.listPrivate(noVault)).single().containsKey("tag"))
    }

    @Test
    fun `tagged and untagged images list together, newest first`() {
        writePrivateImage("wallhaven-older.jpg").setLastModified(1_000L)
        writePrivateImage("wallhaven-newer.png", tag = "anime").setLastModified(9_000L)

        val images = imagesFrom(storage.listPrivate(noVault))

        assertEquals(listOf("wallhaven-newer", "wallhaven-older"), images.map { it["ref"] })
    }

    /**
     * One level, because one level is all tela writes. Anything deeper is
     * something a user put there, and flattening it into a tag would attribute
     * their file to a folder it is not in.
     */
    @Test
    fun `listPrivate does not descend past a tag folder`() {
        val nested = File(privateDirectory("anime"), "deeper").apply { mkdirs() }
        File(nested, "wallhaven-abc123.jpg").writeText("pixels")

        assertTrue(imagesFrom(storage.listPrivate(noVault)).isEmpty())
    }

    /** A directory whose name could not be a tag is skipped whole — the same
     *  judgement made about a file whose name tela did not write. */
    @Test
    fun `a folder that is not a valid tag is skipped`() {
        val hidden = File(privateDirectory(), ".cache").apply { mkdirs() }
        File(hidden, "wallhaven-abc123.jpg").writeText("pixels")

        assertTrue(imagesFrom(storage.listPrivate(noVault)).isEmpty())
    }
}
