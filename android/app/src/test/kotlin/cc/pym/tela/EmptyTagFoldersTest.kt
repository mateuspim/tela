package cc.pym.tela

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Which folders [EmptyTagFolders] may remove once emptied (device pass F9,
 * 2026-10-03). Pure path logic; the SAF delete itself is device-only, as
 * everywhere in these suites.
 *
 * Robolectric for the gallery half: the path is built from
 * `Environment.DIRECTORY_PICTURES`, which the stub `android.jar` leaves null.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class EmptyTagFoldersTest {
    private val card = TreeLocation("1A2B-3C4D", "Wallpapers")
    private val telaTree = TreeLocation("primary", "tela")

    private fun folder(volume: String, path: String) = TreeLocation(volume, path)

    @Test
    fun `a tag folder inside the tela child is one`() {
        assertTrue(EmptyTagFolders.isTagFolder(card, folder("1A2B-3C4D", "Wallpapers/tela/anime")))
    }

    @Test
    fun `the tela folder itself is not`() {
        assertFalse(EmptyTagFolders.isTagFolder(card, folder("1A2B-3C4D", "Wallpapers/tela")))
    }

    @Test
    fun `a vault tag folder is one, the vault is not`() {
        assertTrue(EmptyTagFolders.isTagFolder(card, folder("1A2B-3C4D", "Wallpapers/.tela/anime")))
        assertFalse(EmptyTagFolders.isTagFolder(card, folder("1A2B-3C4D", "Wallpapers/.tela")))
    }

    @Test
    fun `in a granted tela folder, its direct children are the tags`() {
        assertTrue(EmptyTagFolders.isTagFolder(telaTree, folder("primary", "tela/anime")))
        assertFalse(EmptyTagFolders.isTagFolder(telaTree, folder("primary", "tela")))
    }

    @Test
    fun `a hidden folder is never a tag`() {
        assertFalse(EmptyTagFolders.isTagFolder(telaTree, folder("primary", "tela/.tela")))
    }

    @Test
    fun `a folder outside the tree or on another volume is not`() {
        assertFalse(EmptyTagFolders.isTagFolder(card, folder("primary", "Wallpapers/tela/anime")))
        assertFalse(EmptyTagFolders.isTagFolder(card, folder("1A2B-3C4D", "Other/tela/anime")))
    }

    @Test
    fun `a volume-root tree reaches its tags too`() {
        val root = TreeLocation("1A2B-3C4D", "")
        assertTrue(EmptyTagFolders.isTagFolder(root, folder("1A2B-3C4D", "tela/anime")))
    }

    // --- the gallery tier: MediaStore leaves the folder, rmdir takes it ----

    @Test
    fun `a gallery row in a tag folder names its tag`() {
        assertEquals("anime girls", EmptyTagFolders.galleryTagIn("Pictures/tela/anime girls/"))
        assertEquals("anime", EmptyTagFolders.galleryTagIn("pictures/TELA/anime"))
    }

    @Test
    fun `a gallery row loose in tela or anywhere else names none`() {
        assertNull(EmptyTagFolders.galleryTagIn("Pictures/tela/"))
        assertNull(EmptyTagFolders.galleryTagIn("Pictures/"))
        assertNull(EmptyTagFolders.galleryTagIn("DCIM/tela/anime/"))
        assertNull(EmptyTagFolders.galleryTagIn("Pictures/tela/anime/deeper/"))
        assertNull(EmptyTagFolders.galleryTagIn("Pictures/tela/.hidden/"))
    }

    @Test
    fun `an emptied gallery tag folder is removed`() {
        val root = Files.createTempDirectory("shared").toFile()
        val tag = File(root, "Pictures/tela/anime").apply { mkdirs() }

        EmptyTagFolders.pruneGalleryTagsUnder(root, listOf("anime"))

        assertFalse(tag.exists())
        assertTrue("the tela folder itself must stay", File(root, "Pictures/tela").exists())
    }

    @Test
    fun `a gallery tag folder still holding a file stays`() {
        val root = Files.createTempDirectory("shared").toFile()
        val tag = File(root, "Pictures/tela/anime").apply { mkdirs() }
        File(tag, "wallhaven-abc123.jpg").writeText("pixels")

        EmptyTagFolders.pruneGalleryTagsUnder(root, listOf("anime"))

        assertTrue(File(tag, "wallhaven-abc123.jpg").exists())
    }
}
