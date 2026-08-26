package cc.pym.tela

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The hidden folder explicit images go to on the files tier — [VaultFolders],
 * and the [OutsideGalleryTarget] that carries it.
 *
 * Pure string work, so no Robolectric: what is worth pinning here is that the
 * dot is added rather than accepted, and that the traversal guard the tag
 * allowlist provides is not weakened by the one character this adds.
 */
class VaultFoldersTest {
    @Test
    fun `the default label names a hidden directory`() {
        assertEquals(".tela", VaultFolders.directoryOf(VaultFolders.DEFAULT_LABEL))
    }

    /**
     * The dot is composed here, never supplied — which is what makes it
     * impossible to drop and impossible to double.
     */
    @Test
    fun `a label carrying its own dot is refused, not de-duplicated`() {
        assertFalse(VaultFolders.isValidLabel(".stash"))
        assertNull(VaultFolders.directoryOf(".stash"))
    }

    @Test
    fun `a plain label becomes a hidden directory`() {
        assertEquals(".stash", VaultFolders.directoryOf("stash"))
    }

    /**
     * The whole reason the label goes through the tag allowlist: it becomes a
     * directory name, and `..` must never reach a file system call.
     */
    @Test
    fun `traversal and separators are refused`() {
        for (label in listOf("..", ".", "../secrets", "a/b", "", " ")) {
            assertFalse("refuses \"$label\"", VaultFolders.isValidLabel(label))
            assertNull("names nothing for \"$label\"", VaultFolders.directoryOf(label))
        }
    }

    @Test
    fun `spaces are allowed inside a label and refused at its edges`() {
        assertTrue(VaultFolders.isValidLabel("my stash"))
        assertFalse(VaultFolders.isValidLabel(" stash"))
        assertFalse(VaultFolders.isValidLabel("stash "))
    }

    @Test
    fun `a target defaults to the shipped vault`() {
        assertEquals(".tela", OutsideGalleryTarget(null).vaultDirectory)
    }

    /**
     * An unusable label names no directory rather than a repaired one: the
     * write then fails with `unavailable` instead of landing an explicit image
     * in a folder nobody chose.
     */
    @Test
    fun `a target with an unusable label names no directory`() {
        assertNull(OutsideGalleryTarget(null, "../secrets").vaultDirectory)
    }

    /**
     * The visible folder is `tela`; the vault is its dot-prefixed sibling. They
     * must not be the same directory, or the hiding does nothing.
     */
    @Test
    fun `the vault is never the visible tela folder`() {
        assertTrue(OutsideGalleryTarget(null).vaultDirectory != TreeLocation.TELA_FOLDER)
    }
}
