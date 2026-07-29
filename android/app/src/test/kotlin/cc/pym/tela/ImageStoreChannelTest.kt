package cc.pym.tela

import android.app.PendingIntent
import android.content.ContentProvider
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.content.pm.ProviderInfo
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Bundle
import android.os.Looper
import android.provider.MediaStore
import androidx.test.core.app.ApplicationProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
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
 * What storage can still do once the screen is gone.
 *
 * The download queue drains on a cached Flutter engine ([TelaEngine]), so these
 * calls arrive with no activity attached — a batch the user swiped out of
 * recents is the ordinary case, not an edge one. Every method here used to be
 * answered by `MainActivity`, and the two that genuinely need a window now go
 * out through [StoragePrompts] instead of reaching for one that may not exist.
 *
 * So this suite drives the channel with **no prompts attached at all**: the file
 * work must go through, and the two prompts must refuse in a way Dart can read.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ImageStoreChannelTest {
    private lateinit var context: Context
    private lateinit var channel: ImageStoreChannel
    private lateinit var media: FakeDeletableMedia

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        channel = ImageStoreChannel(context)
        media = FakeDeletableMedia()
        // Registering alone leaves the provider with no ProviderInfo, and
        // `createDeleteRequest` refuses to call one whose authority reads null.
        media.attachInfo(context, ProviderInfo().apply { authority = MediaStore.AUTHORITY })
        ShadowContentResolver.registerProviderInternal(MediaStore.AUTHORITY, media)
    }

    private fun imageUri(id: Long): Uri =
        ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)

    private fun galleryItem(id: Long): Map<String, String> =
        mapOf("tier" to "sharedGallery", "location" to imageUri(id).toString())

    /** Writes a file where the app-private tier keeps its downloads. */
    private fun privateFile(name: String): File {
        val directory = File(context.filesDir, "wallpapers").apply { mkdirs() }
        return File(directory, name).apply { writeText("pixels") }
    }

    private fun answerOf(method: String, arguments: Map<String, Any>): Any? {
        val result = CapturedResult()
        channel.handle(MethodCall(method, arguments), result)
        return result.await()
    }

    @Suppress("UNCHECKED_CAST")
    private fun mapAnswer(method: String, arguments: Map<String, Any>): Map<String, Any> =
        answerOf(method, arguments) as Map<String, Any>

    /**
     * The load-bearing one: a download's own delete needs no activity.
     *
     * appPrivate and the SAF tier delete through a Context, and only the gallery
     * tier needs the OS's prompt — so a queue tidying up after itself with no
     * screen open must still be able to remove a file.
     */
    @Test
    fun `an app-private delete goes through with no screen`() {
        val file = privateFile("wallhaven-aaa111.jpg")

        val answer = mapAnswer(
            "deleteDownload",
            mapOf("tier" to "appPrivate", "location" to Uri.fromFile(file).toString()),
        )

        assertEquals(true, answer["success"])
        assertFalse("the file must be gone", file.exists())
    }

    /** The bulk probe is read-only I/O, so it too works without a window. */
    @Test
    fun `the bulk read probe answers with no screen`() {
        val present = privateFile("wallhaven-bbb222.jpg")
        val absent = File(File(context.filesDir, "wallpapers"), "wallhaven-ccc333.jpg")

        val answer = mapAnswer(
            "canReadImages",
            mapOf(
                "locations" to listOf(
                    Uri.fromFile(present).toString(),
                    Uri.fromFile(absent).toString(),
                ),
            ),
        )

        assertEquals(listOf(true, false), answer["readable"])
    }

    /**
     * A folder picker with no activity to open it refuses the way an
     * unconfigured one does, because that is what Dart already knows how to
     * handle: it asks the user again the next time there is a screen.
     */
    @Test
    fun `the folder picker refuses when there is no screen`() {
        val answer = mapAnswer("chooseDownloadFolder", mapOf("kind" to "device"))

        assertEquals(false, answer["success"])
        assertEquals("notConfigured", answer["errorCode"])
    }

    /**
     * The delete prompt is the OS's, so a gallery row cannot go without a screen
     * — but the call must still **answer**. A silent hang here would strand the
     * Dart future waiting to forget those history rows, and the user would see a
     * delete that never finished rather than one that could not run.
     */
    @Test
    fun `a gallery delete refuses when there is no screen`() {
        media.liveIds.add(7L)

        val answer = mapAnswer("deleteDownloads", mapOf("items" to listOf(galleryItem(7L))))

        assertEquals(false, answer["success"])
        assertEquals("unavailable", answer["errorCode"])
    }

    /** A user who accepts the prompt gets the rows they confirmed, and only those. */
    @Test
    fun `an accepted prompt reports the gallery rows`() {
        media.liveIds.add(8L)
        channel.prompts = FakeStoragePrompts(accepts = true)

        val answer = mapAnswer("deleteDownloads", mapOf("items" to listOf(galleryItem(8L))))

        assertEquals(listOf(imageUri(8L).toString()), deleted(answer))
    }

    /**
     * A dismissed prompt is an outcome, not a failure: nothing was deleted, so
     * nothing is forgotten, and the history keeps every row it had.
     */
    @Test
    fun `a declined prompt deletes nothing`() {
        media.liveIds.add(9L)
        channel.prompts = FakeStoragePrompts(accepts = false)

        val answer = mapAnswer("deleteDownloads", mapOf("items" to listOf(galleryItem(9L))))

        assertEquals(true, answer["success"])
        assertEquals(emptyList<String>(), deleted(answer))
    }

    /**
     * A mixed batch reports the files tela deleted itself.
     *
     * The non-gallery files go before any prompt is raised, so whatever the
     * prompt does with the gallery rows must not lose them — Dart forgets
     * exactly the rows named in the answer.
     */
    @Test
    fun `a mixed batch reports what it deleted itself`() {
        val prompts = FakeStoragePrompts(accepts = true)
        channel.prompts = prompts
        val file = privateFile("wallhaven-ddd444.jpg")
        val location = Uri.fromFile(file).toString()

        val answer = mapAnswer(
            "deleteDownloads",
            mapOf(
                "items" to listOf(
                    mapOf("tier" to "appPrivate", "location" to location),
                    mapOf(
                        "tier" to "sharedGallery",
                        "location" to "content://media/external/images/media/8",
                    ),
                ),
            ),
        )

        assertEquals(true, answer["success"])
        assertTrue("the file tela could delete itself must be reported", location in deleted(answer))
        assertFalse("the file must be gone", file.exists())
    }

    /**
     * The screen is lent, not kept. `MainActivity` hands itself over on attach
     * and takes itself back on detach, and holding a destroyed activity through
     * a long background batch is the leak the split exists to prevent.
     */
    @Test
    fun `the prompt host can be withdrawn`() {
        channel.prompts = FakeStoragePrompts(accepts = true)
        channel.prompts = null

        val answer = mapAnswer("chooseDownloadFolder", mapOf("kind" to "device"))

        assertEquals("notConfigured", answer["errorCode"])
    }

    @Suppress("UNCHECKED_CAST")
    private fun deleted(answer: Map<String, Any>): List<String> =
        answer["deleted"] as List<String>

    /**
     * A [MethodChannel.Result] that waits for its answer.
     *
     * Storage work runs off the main thread and replies through a main-thread
     * post, and Robolectric's paused looper never runs those on its own — so
     * awaiting means idling the looper as well as waiting for the worker.
     */
    private class CapturedResult : MethodChannel.Result {
        private var answer: Any? = null
        private var answered = false

        override fun success(result: Any?) {
            answer = result
            answered = true
        }

        override fun error(code: String, message: String?, details: Any?) {
            throw AssertionError("the channel answered with an error: $code $message")
        }

        override fun notImplemented() {
            throw AssertionError("the channel did not implement the call")
        }

        fun await(): Any? {
            repeat(ATTEMPTS) {
                shadowOf(Looper.getMainLooper()).idle()
                if (answered) return answer
                Thread.sleep(POLL_MS)
            }
            throw AssertionError("the channel never answered")
        }

        private companion object {
            const val ATTEMPTS = 300
            const val POLL_MS = 10L
        }
    }

    /**
     * Enough MediaStore to reach the delete prompt: a row that exists, and the
     * `call` behind `createDeleteRequest`, which asks the provider for the
     * PendingIntent the OS would show. Robolectric ships no MediaStore, so
     * without this the batch never gets past [ImageStorage.galleryRowExists] —
     * a row with nothing behind it counts as already deleted.
     */
    private class FakeDeletableMedia : ContentProvider() {
        val liveIds: MutableSet<Long> = mutableSetOf()

        override fun onCreate(): Boolean = true

        override fun query(
            uri: Uri,
            projection: Array<out String>?,
            selection: String?,
            selectionArgs: Array<out String>?,
            sortOrder: String?,
        ): Cursor {
            val cursor = MatrixCursor(arrayOf(MediaStore.MediaColumns._ID))
            val id = ContentUris.parseId(uri)
            if (id in liveIds) cursor.addRow(arrayOf<Any>(id))
            return cursor
        }

        override fun call(method: String, arg: String?, extras: Bundle?): Bundle {
            val pending = PendingIntent.getActivity(
                context!!,
                0,
                Intent(),
                PendingIntent.FLAG_IMMUTABLE,
            )
            return Bundle().apply { putParcelable("result", pending) }
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

    /** A screen that is there, and says what the user chose. */
    private class FakeStoragePrompts(private val accepts: Boolean) : StoragePrompts {
        override fun askFolderGrant(intent: Intent, onAnswer: (Uri?, Int) -> Unit): Boolean {
            onAnswer(if (accepts) Uri.parse("content://tree/granted") else null, 0)
            return true
        }

        override fun askDeleteConfirmation(
            request: IntentSender,
            onAnswer: (Boolean) -> Unit,
        ): Boolean {
            onAnswer(accepts)
            return true
        }
    }
}
