package cc.pym.tela

import android.content.Context
import android.net.Uri
import java.io.File

/**
 * Getting at the bytes of an image tela already stored — for the viewer, not
 * for the tiers.
 *
 * Two questions the download screens ask of a file they did not just write:
 * *can this still be read* (the missing badge), and *give me something Flutter
 * can decode* (the viewer). Both answer failure as an ordinary state rather
 * than a throw, because a wallpaper the user deleted from Photos is a fact
 * about the world, not an error.
 *
 * ```
 * val path = StoredImageReading(context).materialise(location)["path"]
 * ```
 */
internal class StoredImageReading(private val context: Context) {
    /**
     * Whether the file at [location] can still be opened.
     *
     * Opens it rather than asking whether it exists: a MediaStore row can
     * outlive its file, and a SAF grant can be revoked while the document is
     * still listed. The only honest test of "can tela read this" is to read it.
     *
     * Every failure is false, never a throw — a wallpaper the user deleted from
     * Photos is an ordinary state of the world, not an error.
     */
    fun canRead(location: Uri): Map<String, Any> {
        val readable = try {
            if (location.scheme == "file") {
                File(location.path!!).canRead()
            } else {
                context.contentResolver.openInputStream(location)?.use { true } ?: false
            }
        } catch (_: Exception) {
            false
        }
        return mapOf("success" to true, "readable" to readable)
    }

    /**
     * Copies a MediaStore or SAF image into a decodable cache file.
     *
     * Flutter's `FileImage` reads a `file:` path, not a `content:` URI, so the
     * download viewer cannot decode a gallery or document location directly.
     * This copies it into a private cache subfolder and hands back the path;
     * the caller releases it when it moves on. A plain `file:` location never
     * reaches here — Dart points at it directly — so this only ever materialises
     * a URI tela does not own, and never risks copying over the original.
     *
     * Every failure answers `success=false` rather than throwing: a file the
     * user deleted is an ordinary state, and the viewer falls back to Wallhaven.
     */
    fun materialise(location: Uri): Map<String, Any> {
        val directory = TelaDirectories.previews(context)
        if (!TelaDirectories.ensure(directory)) return mapOf("success" to false)
        val target = File(directory, "preview-${System.nanoTime()}")
        return try {
            val copied = context.contentResolver.openInputStream(location)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
                true
            } ?: false
            if (!copied) {
                target.delete()
                mapOf("success" to false)
            } else {
                mapOf("success" to true, "path" to target.absolutePath)
            }
        } catch (_: Exception) {
            target.delete()
            mapOf("success" to false)
        }
    }

    /**
     * Deletes a throwaway preview, refusing any path outside the cache folder.
     *
     * The path arrives back over a method channel, so it is confined to
     * [TelaDirectories.previews] before anything is deleted — the same shape of
     * guard as [TierDeleting.deletePrivate]'s id check, so a preview release can
     * never become an arbitrary-file delete.
     */
    fun releasePreview(path: String): Map<String, Any> {
        val file = File(path)
        val root = TelaDirectories.previews(context)
        val within = try {
            file.canonicalPath.startsWith(root.canonicalPath + File.separator)
        } catch (_: Exception) {
            false
        }
        if (within && file.isFile) file.delete()
        return mapOf("success" to true)
    }
}
