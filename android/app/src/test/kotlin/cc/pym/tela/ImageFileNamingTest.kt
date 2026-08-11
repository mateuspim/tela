package cc.pym.tela

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The name a stored image takes, pinned directly rather than through a write.
 *
 * [ImageStorageTest] already proves these rules where they matter — a traversal
 * id is refused, a Konachan file lists as Konachan's — but it can only reach
 * them through the filesystem. This is the same contract at the seam three
 * modules now share: [TierWriting] composes the name, [PrivateTierListing]
 * parses it back, and [TierDeleting] guards on it, so a change here that only
 * one of them survives is the failure worth catching cheaply.
 *
 * No Robolectric runner: everything here is plain string work, and only
 * [ImageFileNaming.extensionOf] needs a Context — that one stays covered by the
 * copy tests in [ImageStorageTest], which have real files to ask about.
 */
class ImageFileNamingTest {
    @Test
    fun `a file is named for its source and id`() {
        assertEquals("wallhaven-abc123.jpg", ImageFileNaming.fileName("wallhaven", "abc123", "jpg"))
        assertEquals("konachan-406484.png", ImageFileNaming.fileName("konachan", "406484", "png"))
    }

    @Test
    fun `a traversal id never reaches a path`() {
        assertThrows(IllegalArgumentException::class.java) {
            ImageFileNaming.fileName("wallhaven", "../../databases/tela", "jpg")
        }
        assertThrows(IllegalArgumentException::class.java) {
            ImageFileNaming.fileName("../wallhaven", "abc123", "jpg")
        }
    }

    /** The join is `source-id`, so a hyphen on either side would make it ambiguous. */
    @Test
    fun `a hyphen is not part of either half`() {
        assertThrows(IllegalArgumentException::class.java) {
            ImageFileNaming.fileName("wall-haven", "abc123", "jpg")
        }
        assertThrows(IllegalArgumentException::class.java) {
            ImageFileNaming.fileName("wallhaven", "abc-123", "jpg")
        }
    }

    @Test
    fun `the key reads back out of the name`() {
        assertEquals("wallhaven-abc123", ImageFileNaming.keyOf("wallhaven-abc123.jpg"))
        assertEquals("konachan-406484", ImageFileNaming.keyOf("konachan-406484.webp"))
    }

    /**
     * The listing drops anything this returns null for, which is why a file tela
     * did not write can never be reported — or deleted — as one of its own.
     */
    @Test
    fun `a name tela did not write has no key`() {
        assertNull(ImageFileNaming.keyOf("IMG_20260729.jpg"))
        assertNull(ImageFileNaming.keyOf("wallhaven-abc123.txt"))
        assertNull(ImageFileNaming.keyOf(".nomedia"))
    }

    @Test
    fun `only a source-id pair is a valid key`() {
        assertTrue(ImageFileNaming.isValidKey("wallhaven-abc123"))
        assertFalse(ImageFileNaming.isValidKey("../tela.db"))
        assertFalse(ImageFileNaming.isValidKey("abc123"))
    }

    @Test
    fun `an extension comes off the url, ignoring its query`() {
        assertEquals("png", ImageFileNaming.urlExtension("https://example.test/w.png"))
        assertEquals("webp", ImageFileNaming.urlExtension("https://example.test/w.webp?v=2"))
        assertEquals("jpeg", ImageFileNaming.urlExtension("https://example.test/w.JPEG"))
        assertEquals("jpg", ImageFileNaming.urlExtension("https://example.test/w"))
    }

    @Test
    fun `the mime type follows the extension, jpeg by default`() {
        assertEquals("image/png", ImageFileNaming.mimeType("png"))
        assertEquals("image/webp", ImageFileNaming.mimeType("webp"))
        assertEquals("image/jpeg", ImageFileNaming.mimeType("jpg"))
        assertEquals("image/jpeg", ImageFileNaming.mimeType("jpeg"))
    }
}
