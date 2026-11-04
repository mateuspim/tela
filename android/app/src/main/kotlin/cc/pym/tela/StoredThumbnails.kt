package cc.pym.tela

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import org.json.JSONObject

/**
 * Persisted grid thumbnails for stored images — the vault's `content:` documents
 * and the app-private tier's `file:` paths alike.
 *
 * Split out of [StoredImageReading] for three reasons the old in-place version
 * got wrong (owner, 2026-11-04: "30s to open 1"):
 * - it opened the source twice (bounds, then pixels), two binder trips per tile
 *   on a SAF card; one file descriptor now serves both passes;
 * - its cache name was a 32-bit `hashCode`, which can collide and show the
 *   wrong picture, and it wrote in place, so a parallel reader could see half
 *   a file; the name is now a SHA-256 and the write is temp-then-rename;
 * - it ran on the one serial storage thread, so opening a photo waited behind
 *   every queued decode; [executor] is a pool of its own.
 *
 * **Privacy.** Thumbnails live in [TelaDirectories.thumbnails] under the cache
 * dir, never MediaStore, whatever the purity. [forget] removes every size cached
 * for a location, called whenever the file is deleted or moved, so a downsampled
 * explicit picture never outlives its original.
 *
 * ```
 * StoredThumbnails(context).make(location, maxDimensionPx = 400)
 * ```
 */
internal class StoredThumbnails(private val context: Context) {
    /**
     * Answers `{success, path, width, height}` for [location], decoding at
     * roughly [maxDimensionPx] on a cache miss. Every failure is `success=false`.
     *
     * A hit reports the bounds of the small cached file (cheap, local), a miss
     * the source's real bounds; both carry the same aspect ratio.
     */
    fun make(location: Uri, maxDimensionPx: Int): Map<String, Any> {
        val started = System.nanoTime()
        val directory = TelaDirectories.thumbnails(context)
        if (!TelaDirectories.ensure(directory)) return mapOf("success" to false)
        val target = File(directory, cacheName(location, maxDimensionPx))
        val hit = readCached(target)
        val answer = hit ?: decodeAndStore(location, maxDimensionPx, target)
        logTiming(location, hit != null, answer["success"] == true, started)
        return answer
    }

    /** Deletes every cached size of [location]'s thumbnail. Best-effort. */
    fun forget(location: Uri) {
        val prefix = namePrefix(location)
        TelaDirectories.thumbnails(context).listFiles { file -> file.name.startsWith(prefix) }
            ?.forEach { it.delete() }
    }

    private fun readCached(target: File): Map<String, Any>? {
        if (!target.isFile) return null
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(target.absolutePath, options)
        if (options.outWidth <= 0 || options.outHeight <= 0) return null
        return found(target, options.outWidth, options.outHeight)
    }

    private fun decodeAndStore(location: Uri, maxDimensionPx: Int, target: File): Map<String, Any> {
        val temp = File(target.parentFile, "${target.name}.tmp-${System.nanoTime()}")
        return try {
            val (bitmap, width, height) = decodeSampled(location, maxDimensionPx)
                ?: return mapOf("success" to false)
            temp.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, QUALITY, it) }
            bitmap.recycle()
            // Rename is atomic, so a reader sees all of a thumbnail or none.
            if (!temp.renameTo(target)) return mapOf("success" to false)
            found(target, width, height)
        } catch (_: Exception) {
            mapOf("success" to false)
        } finally {
            temp.delete()
        }
    }

    /** One descriptor, two passes: `decodeFileDescriptor` leaves its position alone. */
    private fun decodeSampled(location: Uri, maxDimensionPx: Int): Triple<Bitmap, Int, Int>? {
        val descriptor = context.contentResolver.openFileDescriptor(location, "r") ?: return null
        return descriptor.use {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFileDescriptor(it.fileDescriptor, null, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
            val options = BitmapFactory.Options().apply {
                inSampleSize = sampleSizeFor(bounds.outWidth, bounds.outHeight, maxDimensionPx)
                // Thumbnails are re-encoded as opaque JPEG, so alpha is dead weight.
                inPreferredConfig = Bitmap.Config.RGB_565
            }
            val bitmap = BitmapFactory.decodeFileDescriptor(it.fileDescriptor, null, options)
                ?: return null
            Triple(bitmap, bounds.outWidth, bounds.outHeight)
        }
    }

    private fun found(target: File, width: Int, height: Int): Map<String, Any> = mapOf(
        "success" to true,
        "path" to target.absolutePath,
        "width" to width,
        "height" to height,
    )

    /**
     * One structured line per request for measuring on hardware. Carries timing,
     * cache outcome and tier only — never a path or URI (NSFW rule).
     */
    private fun logTiming(location: Uri, hit: Boolean, ok: Boolean, startedNanos: Long) {
        val line = JSONObject()
            .put("event", "thumbnail")
            .put("ms", (System.nanoTime() - startedNanos) / NANOS_PER_MILLI)
            .put("cache", if (hit) "hit" else "miss")
            .put("ok", ok)
            .put("tier", if (location.scheme == "file") "appPrivate" else "vault")
        Log.d(LOG_TAG, line.toString())
    }

    companion object {
        /** The logcat tag of the timing lines: `adb logcat -s TelaThumb`. */
        const val LOG_TAG = "TelaThumb"
        private const val QUALITY = 85
        private const val NANOS_PER_MILLI = 1_000_000L
        private const val THREADS = 3

        /**
         * Decodes run here, not on the serial storage thread, so opening a photo
         * never queues behind a wall of thumbnails. Small and fixed: decodes are
         * CPU- and memory-heavy, and more threads only fight each other.
         */
        val executor: ExecutorService = Executors.newFixedThreadPool(THREADS)

        /** Hash of [location] alone; every size of one picture shares it. */
        private fun namePrefix(location: Uri): String {
            val digest = MessageDigest.getInstance("SHA-256").digest(location.toString().toByteArray())
            return "thumb-" + digest.take(HASH_BYTES).joinToString("") { "%02x".format(it) } + "-"
        }

        private const val HASH_BYTES = 16

        /** `thumb-<sha256(location)>-<size>.jpg`. */
        fun cacheName(location: Uri, maxDimensionPx: Int): String =
            "${namePrefix(location)}$maxDimensionPx.jpg"
    }
}
