package cc.pym.tela

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
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
     * Decodes a small, downsampled thumbnail for a grid tile, with the
     * source's real pixel bounds alongside it.
     *
     * [SafVaultListing] no longer decodes bounds for the whole vault up
     * front — see its own docs for why that got expensive — so a grid tile
     * asks for its own aspect ratio here, exactly once, the first time it is
     * actually on screen. [materialise] would technically work too, but it
     * copies the *whole* original: fine once for a single full-screen viewer,
     * far too much paid per tile for a wall of dozens of them.
     *
     * Cached by [location] under [TelaDirectories.previews], keyed by its own
     * hash rather than a counter: a tile scrolled past and back must find the
     * same small file already there, not pay for a second decode. A cache hit
     * reads its bounds off that small file's own header — cheap, local, no
     * SAF crossing — rather than reopening the original.
     *
     * Every failure answers `success=false` rather than throwing, the same
     * rule [materialise] follows.
     */
    fun materialiseThumbnail(location: Uri, maxDimensionPx: Int): Map<String, Any> {
        val directory = TelaDirectories.previews(context)
        if (!TelaDirectories.ensure(directory)) return mapOf("success" to false)
        val target = File(directory, "thumb-${location.toString().hashCode()}")
        if (target.isFile) {
            boundsOfFile(target)?.let { (width, height) ->
                return thumbnailResult(target, width, height)
            }
        }
        return try {
            val (sourceWidth, sourceHeight) = boundsOf(location)
                ?: return mapOf("success" to false)
            val options = BitmapFactory.Options().apply {
                inSampleSize = sampleSizeFor(sourceWidth, sourceHeight, maxDimensionPx)
            }
            val bitmap = context.contentResolver.openInputStream(location)?.use { input ->
                BitmapFactory.decodeStream(input, null, options)
            } ?: return mapOf("success" to false)
            target.outputStream().use { output ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, THUMBNAIL_QUALITY, output)
            }
            bitmap.recycle()
            thumbnailResult(target, sourceWidth, sourceHeight)
        } catch (_: Exception) {
            target.delete()
            mapOf("success" to false)
        }
    }

    private fun thumbnailResult(target: File, width: Int, height: Int): Map<String, Any> =
        mapOf(
            "success" to true,
            "path" to target.absolutePath,
            "width" to width,
            "height" to height,
        )

    /** A document's real pixel bounds, read through the resolver. */
    private fun boundsOf(location: Uri): Pair<Int, Int>? {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        return try {
            context.contentResolver.openInputStream(location)?.use { input ->
                BitmapFactory.decodeStream(input, null, options)
            } ?: return null
            validBounds(options)
        } catch (_: Exception) {
            null
        }
    }

    /** The same read, off an already-downsampled local cache file. */
    private fun boundsOfFile(file: File): Pair<Int, Int>? {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, options)
        return validBounds(options)
    }

    private fun validBounds(options: BitmapFactory.Options): Pair<Int, Int>? {
        if (options.outWidth <= 0 || options.outHeight <= 0) return null
        return options.outWidth to options.outHeight
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

    private companion object {
        /** High enough that a grid tile shows no visible banding. */
        const val THUMBNAIL_QUALITY = 85
    }
}
