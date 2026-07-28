package cc.pym.tela

import android.content.Context
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The rule that keeps the two shared tiers out of each other's directory.
 *
 * The files-outside-gallery tier writes a `.nomedia`, and on 2026-07-28 it wrote
 * one into `Pictures/tela` — the gallery tier's own folder — because the user
 * granted `Pictures` at the folder prompt, which is the obvious pick. Eighty
 * downloads plus the owner's own wallpapers left every gallery app at once, with
 * nothing deleted to explain it.
 *
 * Everything here is reachable without SAF: the guard is a decision about a
 * document id, and it deliberately runs *before* anything is created — which is
 * both why it is testable under Robolectric and why it cannot half-apply.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class OutsideGalleryTreeTest {
    private lateinit var storage: ImageStorage

    @Before
    fun setUp() {
        val context: Context = ApplicationProvider.getApplicationContext()
        storage = ImageStorage(context)
    }

    private fun tree(documentId: String): String =
        "content://com.android.externalstorage.documents/tree/" +
            Uri.encode(documentId)

    private fun storeInto(documentId: String): Map<String, Any> = storage.store(
        ImageStoreRequest(
            source = "wallhaven",
            id = "abc123",
            // Unroutable: the guard must answer long before any bytes move.
            imageUrl = "http://127.0.0.1:1/wallpaper.jpg",
            purity = "sfw",
            tier = "filesOutsideGallery",
        ),
        tree(documentId),
    )

    private fun overlapsGallery(documentId: String): Boolean =
        TreeLocation.parse(documentId)!!.overlapsGallery

    // --- the decision -------------------------------------------------------

    @Test
    fun `granting Pictures lands this tier on the gallery's own folder`() {
        // The exact grant that hid eighty wallpapers: Pictures + tela.
        assertTrue(overlapsGallery("primary:Pictures"))
    }

    @Test
    fun `granting the gallery folder itself is refused`() {
        assertTrue(overlapsGallery("primary:Pictures/tela"))
    }

    @Test
    fun `case does not rescue it, because shared storage is case-insensitive`() {
        assertTrue(overlapsGallery("primary:pictures"))
    }

    @Test
    fun `an ordinary folder is fine, including one under Pictures`() {
        assertFalse(overlapsGallery("primary:Download"))
        assertFalse(overlapsGallery("primary:Pictures/wallpapers"))
        assertFalse(overlapsGallery("primary:"))
    }

    @Test
    fun `a card's own Pictures is nobody else's directory`() {
        // The gallery tier inserts into the primary volume's MediaStore, so the
        // same path on a card collides with nothing and must stay usable.
        assertFalse(overlapsGallery("1A2B-3C4D:Pictures"))
    }

    // --- the refusal, where it has to live ----------------------------------

    @Test
    fun `the storage adapter refuses a colliding tree, not just the picker`() {
        val result = storeInto("primary:Pictures")

        assertEquals(false, result["success"])
        // folderUnavailable, not unavailable: the folder is set and the fix is
        // to pick another one, which is what that message says.
        assertEquals("folderUnavailable", result["errorCode"])
    }

    @Test
    fun `a uri that is not a tree answers no location rather than throwing`() {
        // `DocumentsContract.getTreeDocumentId` throws on one of these, and the
        // grant path asks this question on the main thread.
        assertNull(
            TreeLocation.of(
                Uri.parse(
                    "content://com.android.externalstorage.documents" +
                        "/document/primary%3APictures",
                ),
            ),
        )
    }

    @Test
    fun `a tree that is not a tree at all is refused, not written to`() {
        val result = storage.store(
            ImageStoreRequest(
                source = "wallhaven",
                id = "abc123",
                imageUrl = "http://127.0.0.1:1/wallpaper.jpg",
                purity = "sfw",
                tier = "filesOutsideGallery",
            ),
            "content://com.android.externalstorage.documents/document/primary%3APictures",
        )

        assertEquals(false, result["success"])
        assertEquals("folderUnavailable", result["errorCode"])
    }

    @Test
    fun `a folder of tela's own is not refused by this guard`() {
        // It still fails — Robolectric emulates no SAF — but never as the
        // collision, which is the only thing this guard is entitled to say.
        assertNotEquals("folderUnavailable", storeInto("primary:Download")["errorCode"])
    }
}
