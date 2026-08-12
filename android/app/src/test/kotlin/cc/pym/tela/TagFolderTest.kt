package cc.pym.tela

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * What may become a directory name, and where each tier puts it — [TagFolders].
 *
 * The allowlist here is a **path-traversal gate**, not a tidiness rule: a tag
 * arrives over a method channel and is concatenated into a directory, so this is
 * the same class of guard as [ImageFileNaming]'s and it is tested the same way —
 * by naming the shapes that must never reach a file system call.
 *
 * SDK 35 (`compileSdk`) rather than the app's targetSdk 36, for the reason
 * [ImageStorageTestCase] gives: Robolectric ships framework jars only for the
 * SDKs it has been released against.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class TagFolderTest {
    private lateinit var context: Context

    @Before
    fun openContext() {
        context = ApplicationProvider.getApplicationContext()
    }

    // --- the allowlist ------------------------------------------------------

    @Test
    fun `ordinary tag names are accepted`() {
        for (tag in listOf("anime", "Nature", "sci fi", "hatsune_miku", "4k-walls", "2026")) {
            assertTrue("tag $tag", TagFolders.isValid(tag))
        }
    }

    /**
     * Every one of these is refused by the *same* rule — no `.` and no
     * separator — rather than by a case each. That is why the class excludes the
     * dot outright: `..`, a hidden directory and the `.nomedia` marker this tier
     * depends on all stop being reachable without anyone reasoning about them
     * individually.
     */
    @Test
    fun `a traversing or hidden name is refused`() {
        for (tag in listOf("..", ".", "../secrets", "a/b", "a\\b", ".nomedia", ".hidden")) {
            assertFalse("tag $tag", TagFolders.isValid(tag))
        }
    }

    @Test
    fun `an empty or over-long name is refused`() {
        assertFalse(TagFolders.isValid(""))
        assertFalse(TagFolders.isValid("x".repeat(33)))
        assertTrue(TagFolders.isValid("x".repeat(32)))
    }

    /**
     * Untrimmed and exotic input is refused rather than quietly repaired: the
     * Dart side normalises, and this side does not trust that it did.
     *
     * The padded pair is the one worth having. A space is legal *inside* a tag,
     * so a flat character class accepts " anime" — a folder that renders
     * identically to "anime" in every list the user will ever see while being a
     * different directory on disk. A tag nobody can tell from another is worse
     * than a refused one.
     */
    @Test
    fun `padding and unusual characters are refused`() {
        for (tag in listOf(" anime", "anime ", " ", "an\nime", "caf\u00e9", "\u2605")) {
            assertFalse("tag $tag", TagFolders.isValid(tag))
        }
    }

    /** A space between words is kept, and is why the padding rule needed its own
     *  bracket rather than dropping the space from the class entirely. */
    @Test
    fun `a space inside a tag is kept`() {
        assertTrue(TagFolders.isValid("sci fi"))
        assertTrue(TagFolders.isValid("a b c"))
    }

    // --- where each tier puts it -------------------------------------------

    /**
     * The gallery path is one composition because two of them would break the
     * duplicate lookup: `TierWriting` scopes its "have I written this already?"
     * query to a directory, so a second spelling would make a re-download insert
     * a copy instead of rewriting the file it has.
     */
    @Test
    fun `the gallery path is the tela folder, or a tag inside it`() {
        assertEquals(TreeLocation.GALLERY_FOLDER_PATH, TagFolders.galleryPath(null))
        assertEquals("${TreeLocation.GALLERY_FOLDER_PATH}/anime", TagFolders.galleryPath("anime"))
    }

    @Test
    fun `the private directory is the tier root, or a tag inside it`() {
        val root = TelaDirectories.privateImages(context)

        assertEquals(root, TagFolders.privateDirectory(context, null))
        assertEquals(File(root, "anime"), TagFolders.privateDirectory(context, "anime"))
    }

    /** The refusal is a return value, so the caller answers `unavailable`
     *  instead of the process dying on a tag somebody typed. */
    @Test
    fun `the private directory refuses a traversing tag`() {
        assertNull(TagFolders.privateDirectory(context, "../databases"))
    }

    // --- reading the tag back off a file -----------------------------------

    @Test
    fun `a file one folder down reports that folder as its tag`() {
        val root = TelaDirectories.privateImages(context)
        val tagged = File(File(root, "anime"), "wallhaven-abc123.jpg")

        assertEquals("anime", TagFolders.tagOf(context, tagged))
    }

    @Test
    fun `a file in the tier root reports no tag`() {
        val loose = File(TelaDirectories.privateImages(context), "wallhaven-abc123.jpg")

        assertNull(TagFolders.tagOf(context, loose))
    }
}
