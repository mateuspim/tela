package cc.pym.tela

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which folders [EmptyTagFolders] may remove once emptied (device pass F9,
 * 2026-10-03). Pure path logic; the SAF delete itself is device-only, as
 * everywhere in these suites.
 */
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
}
