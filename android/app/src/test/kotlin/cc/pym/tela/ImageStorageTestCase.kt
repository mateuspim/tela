package cc.pym.tela

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import java.io.File
import org.junit.Before

/**
 * What every [ImageStorage] test needs: a context, the facade, and the app-private
 * tier's directory.
 *
 * These four suites were one 536-line file until 2026-08-11, when it was split
 * along the collaborators [ImageStorage] itself is built from — [TierWriting],
 * [TierDeleting], [PrivateTierListing] and [StoredImageReading], one suite each.
 * The helpers stayed together here rather than being copied four ways.
 *
 * **Scope is deliberate, and it is the same for all four**: everything reachable
 * from here works **without** MediaStore or a SAF tree, which Robolectric does
 * not usefully emulate. That still covers the things worth defending
 * mechanically — the NSFW indexing rule, and the path guards that keep a
 * method-channel string from becoming an arbitrary-file delete. The MediaStore
 * and SAF write paths remain device-only; see HANDOFF.
 *
 * Every subclass pins **SDK 35** (`compileSdk`), not the app's `targetSdk` 36,
 * because Robolectric only ships framework jars for SDKs it has been released
 * against. It is repeated on each rather than inherited so that a suite read on
 * its own says which framework it ran against.
 */
abstract class ImageStorageTestCase {
    protected lateinit var context: Context
    protected lateinit var storage: ImageStorage

    @Before
    fun openStorage() {
        context = ApplicationProvider.getApplicationContext()
        storage = ImageStorage(context)
    }

    /** The app-private tier on disk — the one tier these tests can really write. */
    protected fun privateDirectory(): File = File(context.filesDir, "wallpapers")

    /** Puts a file in the private tier as if tela had downloaded it there. */
    protected fun writePrivateImage(name: String, contents: String = "pixels"): File {
        val directory = privateDirectory()
        directory.mkdirs()
        return File(directory, name).apply { writeText(contents) }
    }

    protected fun errorCodeOf(result: Map<String, Any>): String? = result["errorCode"] as String?

    @Suppress("UNCHECKED_CAST")
    protected fun imagesFrom(result: Map<String, Any>): List<Map<String, Any>> =
        result["images"] as List<Map<String, Any>>
}
