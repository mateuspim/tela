package cc.pym.tela

import android.content.ContentProvider
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.provider.MediaStore
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowContentResolver

/**
 * The check that stands between a stale history row and a killed process.
 *
 * Clearing download history crashed the app on 2026-07-28, unrecoverably:
 * `MediaStore.createDeleteRequest` throws `IllegalArgumentException` for a URI
 * whose row is gone, it ran on the main thread, and the only gesture that
 * removes those rows is the one that crashed — so every retry died before
 * trimming anything and the user was stuck short of wiping app data.
 *
 * `MainActivity.planDeletions` keeps such a URI out of that call by asking
 * [ImageStorage.galleryRowExists] first. This covers both of its answers against
 * a stand-in media provider, since Robolectric ships no MediaStore.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class GalleryRowLivenessTest {
    private lateinit var storage: ImageStorage
    private lateinit var media: FakeMediaProvider

    @Before
    fun setUp() {
        val context: Context = ApplicationProvider.getApplicationContext()
        storage = ImageStorage(context)
        media = FakeMediaProvider()
        ShadowContentResolver.registerProviderInternal(MediaStore.AUTHORITY, media)
    }

    private fun imageUri(id: Long): Uri =
        ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)

    @Test
    fun `a row MediaStore still has is live`() {
        media.liveIds.add(178222L)

        assertTrue(storage.galleryRowExists(imageUri(178222L)))
    }

    @Test
    fun `a row deleted behind tela's back is not`() {
        // The download history outlives the file whenever it goes away by other
        // means — Photos, a file manager, a storage cleaner, an unmounted card.
        assertFalse(storage.galleryRowExists(imageUri(178222L)))
    }

    @Test
    fun `a provider that throws answers no, never a throw of its own`() {
        media.failing = true

        assertFalse(storage.galleryRowExists(imageUri(178222L)))
    }
}

/**
 * The one MediaStore behaviour the liveness check rests on: a query for an image
 * URI answers a row when that image exists and an empty cursor when it does not.
 */
private class FakeMediaProvider : ContentProvider() {
    val liveIds: MutableSet<Long> = mutableSetOf()
    var failing: Boolean = false

    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        if (failing) throw IllegalArgumentException("no such volume, got \"$uri\"")
        val cursor = MatrixCursor(arrayOf(MediaStore.MediaColumns._ID))
        val id = ContentUris.parseId(uri)
        if (id in liveIds) cursor.addRow(arrayOf<Any>(id))
        return cursor
    }

    override fun getType(uri: Uri): String = "image/jpeg"

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0
}
