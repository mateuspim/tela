package cc.pym.tela

import org.junit.Assert.assertEquals
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
}
