package cc.pym.tela

import android.net.Uri
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Moving a stored image between tag folders — [StoredImageRetagging], through
 * [ImageStorage].
 *
 * The app-private tier is the one this suite can really exercise, and it is also
 * the one whose move is a plain rename; the gallery's `RELATIVE_PATH` update and
 * the SAF `moveDocument` need a MediaStore and a granted tree, which Robolectric
 * does not usefully emulate (see [ImageStorageTestCase]). What is pinned here is
 * the part that would be a security bug rather than a broken feature: a location
 * arriving over a method channel cannot move a file that is not tela's, and
 * cannot move one anywhere but inside the tier.
 *
 * The **new location is the answer**, and every test reads it: the caller has to
 * store it, because a history row still pointing at the old path describes a
 * file that is not there.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class StoredImageRetaggingTest : ImageStorageTestCase() {
    @Test
    fun `an untagged image moves into a tag folder`() {
        val file = writePrivateImage("wallhaven-abc123.jpg")

        val result = storage.retag("appPrivate", Uri.fromFile(file), "anime", null)

        assertEquals(true, result["success"])
        assertFalse(file.exists())
        val moved = File(privateDirectory("anime"), "wallhaven-abc123.jpg")
        assertTrue(moved.exists())
        assertEquals(Uri.fromFile(moved).toString(), result["location"])
    }

    @Test
    fun `an image moves from one tag to another`() {
        val file = writePrivateImage("wallhaven-abc123.jpg", tag = "anime")

        storage.retag("appPrivate", Uri.fromFile(file), "minimal", null)

        assertFalse(file.exists())
        assertTrue(File(privateDirectory("minimal"), "wallhaven-abc123.jpg").exists())
    }

    // Regression for device pass F9 (2026-10-03): moving a tag's last
    // wallpaper out left the empty folder behind.
    @Test
    fun `moving a tag's last wallpaper out removes the emptied folder`() {
        val file = writePrivateImage("wallhaven-abc123.jpg", tag = "anime")

        storage.retag("appPrivate", Uri.fromFile(file), "minimal", null)

        assertFalse(privateDirectory("anime").exists())
    }

    /** A null tag is a destination, not a refusal: it is how an image comes back
     *  out of a tag without needing an "untagged" folder to exist. */
    @Test
    fun `a null tag moves the image back to the tier root`() {
        val file = writePrivateImage("wallhaven-abc123.jpg", tag = "anime")

        val result = storage.retag("appPrivate", Uri.fromFile(file), null, null)

        assertEquals(true, result["success"])
        assertTrue(File(privateDirectory(), "wallhaven-abc123.jpg").exists())
    }

    /** Retagging into the tag it is already in is a no-op that succeeds — the
     *  caller may be applying one tag across a mixed selection. */
    @Test
    fun `retagging into the same tag leaves the file where it is`() {
        val file = writePrivateImage("wallhaven-abc123.jpg", tag = "anime")

        val result = storage.retag("appPrivate", Uri.fromFile(file), "anime", null)

        assertEquals(true, result["success"])
        assertTrue(file.exists())
        assertEquals(Uri.fromFile(file).toString(), result["location"])
    }

    // --- what it must refuse ------------------------------------------------

    /** The tag builds a directory, so it passes the same gate the write path
     *  applies — before anything is renamed. */
    @Test
    fun `a traversing tag is refused and nothing moves`() {
        val file = writePrivateImage("wallhaven-abc123.jpg")

        val result = storage.retag("appPrivate", Uri.fromFile(file), "../..", null)

        assertEquals(false, result["success"])
        assertEquals("unavailable", errorCodeOf(result))
        assertTrue(file.exists())
    }

    /**
     * The location is the other untrusted argument, and this is the one that
     * would matter: without the confinement, a retag is a general-purpose file
     * move over anything the app can reach.
     */
    @Test
    fun `a location outside the private tier is refused`() {
        val outside = File(context.filesDir, "wallhaven-abc123.jpg").apply { writeText("db") }

        val result = storage.retag("appPrivate", Uri.fromFile(outside), "anime", null)

        assertEquals(false, result["success"])
        assertTrue("the file outside the tier was moved", outside.exists())
    }

    /** A name tela did not write has no business being moved by tela — the same
     *  rule that keeps such a file out of the listing. */
    @Test
    fun `a file tela did not name is refused`() {
        val stray = writePrivateImage("holiday.jpg")

        val result = storage.retag("appPrivate", Uri.fromFile(stray), "anime", null)

        assertEquals(false, result["success"])
        assertTrue(stray.exists())
    }

    @Test
    fun `an unknown tier is refused rather than guessed at`() {
        val result = storage.retag("downloads", Uri.parse("file:///x.jpg"), "anime", null)

        assertEquals(false, result["success"])
        assertEquals("unavailable", errorCodeOf(result))
    }

    /** No granted tree means the files tier has nowhere to move within, and it
     *  says so with the code the download path already uses for it. */
    @Test
    fun `the files tier without a granted folder answers notConfigured`() {
        val result = storage.retag(
            "filesOutsideGallery",
            Uri.parse("content://com.android.externalstorage.documents/tree/primary%3A/x.jpg"),
            "anime",
            null,
        )

        assertEquals("notConfigured", errorCodeOf(result))
    }
}
