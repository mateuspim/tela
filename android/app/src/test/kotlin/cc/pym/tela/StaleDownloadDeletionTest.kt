package cc.pym.tela

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.provider.DocumentsContract
import androidx.test.core.app.ApplicationProvider
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowContentResolver

/**
 * Deleting a download whose file is already gone.
 *
 * **A file that is already gone counts as deleted**, because it is: the end
 * state the user asked for has been reached by other means. That decision was
 * made on 2026-07-28 for the gallery tier, where a stale row *crashed* the
 * process — and it was applied only there. The other two tiers kept answering
 * `unavailable`, which fails in silence, and silence is the worse failure:
 * `DeleteDownloads` forgets only the rows whose files came back deleted, so a
 * stale `filesOutsideGallery` or `appPrivate` row could **never be removed from
 * download history**. Select it, tap delete, nothing happens, no error.
 *
 * Reported by the owner on 2026-07-28 against a history full of rows whose
 * files had been removed out of band. It needs no mistake of tela's: a file
 * manager, a USB session, a storage cleaner or an ejected card all do it.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class StaleDownloadDeletionTest {
    private lateinit var context: Context
    private lateinit var storage: ImageStorage

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        storage = ImageStorage(context)
    }

    private fun privateImage(name: String): File {
        val directory = File(context.filesDir, "wallpapers")
        directory.mkdirs()
        return File(directory, name).apply { writeText("pixels") }
    }

    /**
     * The path guard outranks the new leniency, and this is the one case where
     * the two could have collided: "already gone" must never become a way to
     * ask about a file outside the private directory. The appPrivate side of
     * the rule itself lives in `ImageStorageTest`, beside the guard.
     */
    @Test
    fun `a traversing key is still refused, not called already gone`() {
        privateImage("wallhaven-abc123.jpg")

        val response = storage.deletePrivate("../../databases/tela")

        assertEquals(false, response["success"])
        assertEquals("unavailable", response["errorCode"])
    }

    @Test
    fun `a document that is already gone reads as deleted`() {
        val documents = FakeDocumentProvider(holds = false)
        ShadowContentResolver.registerProviderInternal(AUTHORITY, documents)

        val response = storage.deleteDownload("filesOutsideGallery", documentUri())

        assertEquals(true, response["success"])
    }

    /**
     * The distinction that makes this safe: a document the provider still holds
     * but refuses to delete is a real failure and must stay one, or a genuinely
     * failed delete would silently drop its history row and lose the user's
     * only handle on a file still sitting on disk.
     */
    @Test
    fun `a document that exists but will not delete is still a failure`() {
        val documents = FakeDocumentProvider(holds = true)
        ShadowContentResolver.registerProviderInternal(AUTHORITY, documents)

        val response = storage.deleteDownload("filesOutsideGallery", documentUri())

        assertEquals(false, response["success"])
        assertEquals("unavailable", response["errorCode"])
    }

    @Test
    fun `a provider that throws on the existence check reads as deleted`() {
        // A revoked grant or an ejected card. tela cannot reach the file, and an
        // unclearable history row for it helps nobody.
        val documents = FakeDocumentProvider(holds = true, throwsOnQuery = true)
        ShadowContentResolver.registerProviderInternal(AUTHORITY, documents)

        val response = storage.deleteDownload("filesOutsideGallery", documentUri())

        assertEquals(true, response["success"])
    }

    private fun documentUri(): Uri =
        Uri.parse("content://$AUTHORITY/tree/primary%3ADownload/document/primary%3ADownload%2Ftela%2Fa.jpg")

    /**
     * Stands in for the storage-access provider, which Robolectric does not
     * emulate. Robolectric's own `deleteDocument` shadow always reports failure,
     * which is the very case under test — what the provider then says about the
     * document's *existence* is what decides the answer.
     */
    private class FakeDocumentProvider(
        private val holds: Boolean,
        private val throwsOnQuery: Boolean = false,
    ) : ContentProvider() {
        override fun onCreate(): Boolean = true

        override fun query(
            uri: Uri,
            projection: Array<out String>?,
            selection: String?,
            selectionArgs: Array<out String>?,
            sortOrder: String?,
        ): Cursor? {
            if (throwsOnQuery) throw SecurityException("grant revoked")
            val cursor = MatrixCursor(arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID))
            if (holds) cursor.addRow(arrayOf("primary:Download/tela/a.jpg"))
            return cursor
        }

        override fun getType(uri: Uri): String? = "image/jpeg"
        override fun insert(uri: Uri, values: ContentValues?): Uri? = null
        override fun delete(uri: Uri, selection: String?, args: Array<out String>?): Int = 0
        override fun update(
            uri: Uri,
            values: ContentValues?,
            selection: String?,
            args: Array<out String>?,
        ): Int = 0
    }

    private companion object {
        const val AUTHORITY = "com.android.externalstorage.documents"
    }
}
