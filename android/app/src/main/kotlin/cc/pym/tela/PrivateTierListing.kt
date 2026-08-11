package cc.pym.tela

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.File

/**
 * Reading back the app-private tier, newest first.
 *
 * Only this tier is listable: the other two land where the system gallery or a
 * file manager already shows them. These files are visible to nothing but tela,
 * so without this they can only be written, never seen.
 *
 * ```
 * val images = PrivateTierListing(context).listPrivate()["images"]
 * ```
 */
internal class PrivateTierListing(private val context: Context) {
    /** Every private image, newest first, with the bounds the grid shapes tiles to. */
    fun listPrivate(): Map<String, Any> {
        val files = TelaDirectories.privateImages(context)
            .listFiles()
            ?.filter { it.isFile }
            ?: emptyList()
        val images = files
            .sortedByDescending { it.lastModified() }
            .mapNotNull { file -> describe(file) }
        return mapOf("success" to true, "images" to images)
    }

    /**
     * One image's row, or null for a file tela did not write.
     *
     * The name is the identity: a file whose name does not parse has no source
     * and no id to report, and reporting it under a guess is worse than
     * omitting it.
     */
    private fun describe(file: File): Map<String, Any>? {
        val key = ImageFileNaming.keyOf(file.name) ?: return null
        val (width, height) = pixelBounds(file)
        return mapOf(
            "ref" to key,
            "location" to Uri.fromFile(file).toString(),
            "savedAt" to file.lastModified(),
            "sizeBytes" to file.length(),
            "width" to width,
            "height" to height,
        )
    }

    /**
     * Reads a file's pixel dimensions without decoding its pixels.
     *
     * `inJustDecodeBounds` fills `outWidth`/`outHeight` from the header alone, so
     * the private grid can shape each tile to its file without holding a whole
     * 6K bitmap in memory. A corrupt or truncated file leaves both at -1, which
     * Dart reads back as unknown and renders as a safe broken-image state.
     */
    private fun pixelBounds(file: File): Pair<Int, Int> {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        return try {
            BitmapFactory.decodeFile(file.absolutePath, options)
            options.outWidth to options.outHeight
        } catch (_: Exception) {
            -1 to -1
        }
    }
}
