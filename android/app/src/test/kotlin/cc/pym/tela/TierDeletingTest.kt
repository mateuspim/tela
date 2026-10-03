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
 * Taking an image back out of a tier — [TierDeleting], through [ImageStorage].
 *
 * Two rules run through all of it: a key or location that names something tela
 * did not write **deletes nothing**, and a file that is **already gone counts as
 * deleted** — the 2026-07-28 reversal argued in full in [StaleDownloadDeletionTest].
 *
 * See [ImageStorageTestCase] for what this suite can and cannot reach.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class TierDeletingTest : ImageStorageTestCase() {
    // --- deletePrivate, and the path guard ----------------------------------

    @Test
    fun `deletePrivate removes the file for its key`() {
        val file = writePrivateImage("wallhaven-abc123.jpg")

        val result = storage.deletePrivate("wallhaven-abc123")

        assertEquals(true, result["success"])
        assertFalse(file.exists())
    }

    /**
     * The id arrives over a method channel, so a traversing one must not reach
     * a file. Note what actually defends this: `deletePrivate` **filters a
     * listing** rather than building a path, so the traversal has nowhere to go
     * even with `VALID_ID` removed — verified by mutation, where this test kept
     * passing. It pins the outcome, which is the claim that matters; the regex
     * is pinned instead by the store path, where a path *is* built from the id
     * (see [TierWritingTest]).
     */
    @Test
    fun `deletePrivate refuses a traversing key and deletes nothing`() {
        val outside = File(context.filesDir, "tela.db").apply { writeText("database") }

        val result = storage.deletePrivate("../tela.db")

        assertEquals(false, result["success"])
        assertEquals("unavailable", errorCodeOf(result))
        assertTrue("the file outside the tier survived", outside.exists())
    }

    /**
     * **Changed on 2026-07-28, deliberately** — this used to assert failure, and
     * asserting it is what kept the bug in place. A file that is already gone
     * counts as deleted, because it is; answering `unavailable` left a download
     * history row that could never be removed. See `StaleDownloadDeletionTest`
     * for the whole argument. The traversal guard above is untouched.
     */
    @Test
    fun `deletePrivate counts a key it holds no file for as deleted`() {
        writePrivateImage("wallhaven-abc123.jpg")

        val result = storage.deletePrivate("wallhaven-zzz999")

        assertEquals(true, result["success"])
    }

    /**
     * Why the key is source-qualified rather than the bare id it used to be:
     * `deletePrivate` deletes **every** file its filter matches, so two sources
     * issuing the same number would have deleted each other's image. Konachan
     * and yande.re really do share an id space this way.
     */
    @Test
    fun `deletePrivate does not reach another source's file with the same id`() {
        val konachan = writePrivateImage("konachan-406484.jpg")
        val other = writePrivateImage("yandere-406484.jpg")

        val result = storage.deletePrivate("konachan-406484")

        assertEquals(true, result["success"])
        assertFalse(konachan.exists())
        assertTrue("another source's file with the same id was deleted", other.exists())
    }

    // --- deleteDownload, the hard delete (J) --------------------------------

    /**
     * The app-private branch recovers the key from the file's own name and reuses
     * [ImageStorage.deletePrivate], so its listing-filter guard still stands —
     * the only tier Robolectric can exercise, the other two being MediaStore and
     * SAF (device-only, as elsewhere in these suites).
     */
    @Test
    fun `deleteDownload removes an app-private file and reports it deleted`() {
        val file = writePrivateImage("wallhaven-abc123.jpg")

        val result = storage.deleteDownload("appPrivate", Uri.fromFile(file))

        assertEquals(true, result["success"])
        assertEquals(listOf(Uri.fromFile(file).toString()), result["deleted"])
        assertFalse(file.exists())
    }

    /** A location whose name is not one tela wrote yields no id, so nothing is
     *  deleted — the guard against a method-channel path becoming a file delete. */
    @Test
    fun `deleteDownload refuses an app-private location tela did not write`() {
        val outside = File(context.filesDir, "tela.db").apply { writeText("database") }

        val result = storage.deleteDownload("appPrivate", Uri.fromFile(outside))

        assertEquals(false, result["success"])
        assertEquals("unavailable", errorCodeOf(result))
        assertTrue("the file outside the tier survived", outside.exists())
    }

    /**
     * The same reversal as `deletePrivate counts a key it holds no file for`.
     *
     * The location is built from the real tier directory rather than written out
     * as `/data/user/0/…`. It used to be a literal, and that passed only because
     * this path read the *file name* and threw the directory away — once the
     * delete became location-exact (tags mean one wallpaper can be in two
     * folders) the literal named somewhere outside Robolectric's `filesDir` and
     * was correctly refused as out-of-tier. A fixture that has to lie about
     * where a file is was pinning the old shortcut, not the rule.
     */
    @Test
    fun `deleteDownload counts an app-private id it holds no file for as deleted`() {
        writePrivateImage("wallhaven-abc123.jpg")
        val absent = File(privateDirectory(), "wallhaven-zzz999.jpg")

        val result = storage.deleteDownload("appPrivate", Uri.fromFile(absent))

        assertEquals(true, result["success"])
    }

    @Test
    fun `deleteDownload refuses an unknown tier rather than guessing`() {
        val result = storage.deleteDownload("downloads", Uri.parse("file:///x.jpg"))

        assertEquals(false, result["success"])
        assertEquals("unavailable", errorCodeOf(result))
    }

    // --- tags, which are folders -------------------------------------------

    /**
     * **The silent one.** This path treats "no matching file" as success, on the
     * sound rule that a file already gone counts as deleted. A search that did
     * not descend into tag folders would therefore report every tagged image
     * deleted and remove none of them — no exception, no error code, nothing in
     * a log. Verified by mutation: dropping the tag folders from
     * [TelaDirectories.privateFiles] turns this red and nothing else.
     */
    @Test
    fun `deletePrivate reaches a file inside a tag folder`() {
        val file = writePrivateImage("wallhaven-abc123.jpg", tag = "anime")

        val result = storage.deletePrivate("wallhaven-abc123")

        assertEquals(true, result["success"])
        assertFalse("the tagged file survived a delete that reported success", file.exists())
    }

    /** By key means the wallpaper, wherever it is: this door names an image, not
     *  a file, and a copy left behind in another tag is a delete that lied. */
    @Test
    fun `deletePrivate removes every tag's copy of one wallpaper`() {
        val anime = writePrivateImage("wallhaven-abc123.jpg", tag = "anime")
        val minimal = writePrivateImage("wallhaven-abc123.jpg", tag = "minimal")

        storage.deletePrivate("wallhaven-abc123")

        assertFalse(anime.exists())
        assertFalse(minimal.exists())
    }

    /**
     * By location means **that** file. Deleting one tile must not empty the
     * other tag — which is exactly what this path used to do, because it read
     * the file name and threw the directory away. Harmless while the tier was
     * flat; wrong the moment a tag became a folder.
     */
    @Test
    fun `deleteDownload takes only the copy at the location it was given`() {
        val anime = writePrivateImage("wallhaven-abc123.jpg", tag = "anime")
        val minimal = writePrivateImage("wallhaven-abc123.jpg", tag = "minimal")

        val result = storage.deleteDownload("appPrivate", Uri.fromFile(anime))

        assertEquals(true, result["success"])
        assertFalse(anime.exists())
        assertTrue("the other tag's copy was taken too", minimal.exists())
    }

    // --- emptied tag folders (device pass F9, 2026-10-03) ------------------

    @Test
    fun `deleting a tag's last wallpaper removes the emptied tag folder`() {
        val file = writePrivateImage("wallhaven-abc123.jpg", tag = "anime")

        storage.deleteDownload("appPrivate", Uri.fromFile(file))

        assertFalse("the empty tag folder was left behind", privateDirectory("anime").exists())
    }

    @Test
    fun `a tag folder that still holds a wallpaper stays`() {
        val file = writePrivateImage("wallhaven-abc123.jpg", tag = "anime")
        writePrivateImage("wallhaven-def456.jpg", tag = "anime")

        storage.deleteDownload("appPrivate", Uri.fromFile(file))

        assertTrue(privateDirectory("anime").exists())
    }

    @Test
    fun `deleting the last untagged wallpaper keeps the tier's own folder`() {
        val file = writePrivateImage("wallhaven-abc123.jpg")

        storage.deleteDownload("appPrivate", Uri.fromFile(file))

        assertTrue(privateDirectory().exists())
    }

    @Test
    fun `deleting by key prunes every tag folder it empties`() {
        writePrivateImage("wallhaven-abc123.jpg", tag = "anime")
        writePrivateImage("wallhaven-abc123.jpg", tag = "minimal")

        storage.deletePrivate("wallhaven-abc123")

        assertFalse(privateDirectory("anime").exists())
        assertFalse(privateDirectory("minimal").exists())
    }
}
