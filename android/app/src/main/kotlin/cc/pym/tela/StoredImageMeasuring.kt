package cc.pym.tela

import android.content.Context
import android.net.Uri
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import java.io.File

/**
 * How big a stored image is, and whether it is already off the built-in disk.
 *
 * The two facts the offload screen adds up. Both have to come from the same
 * pass: a group is only worth showing if it names how much moving it frees, and
 * "frees" is only true for a file that is *not* on the card already — counting a
 * card file into the tally would promise space the device never gets back.
 *
 * Read-only, and every failure is a zero-byte, non-removable answer rather than
 * a throw: a file the user deleted from Photos is an ordinary state of the
 * world here, exactly as it is for [StoredImageReading.canRead].
 *
 * ```
 * StoredImageMeasuring(context).measure(location) // {bytes=1048576, removable=false}
 * ```
 */
internal class StoredImageMeasuring(private val context: Context) {
    /** Bytes on disk and removability for [location], zeroed when unreadable. */
    fun measure(location: Uri): Map<String, Any> = mapOf(
        "bytes" to bytesOf(location),
        "removable" to isRemovable(location),
    )

    /**
     * The size of the file at [location], or 0 when it cannot be read.
     *
     * Three schemes, three routes: a `file:` URI is a path, a document has a
     * `_SIZE` column, and anything else falls back to opening a descriptor.
     * MediaStore answers the column too, so the fallback is only ever reached by
     * a provider that publishes neither — and a length of `-1` from an unknown
     * one is not a size, so it reads as zero.
     */
    private fun bytesOf(location: Uri): Long {
        if (location.scheme == "file") {
            val file = File(location.path ?: return 0L)
            return if (file.isFile) file.length() else 0L
        }
        return columnSize(location) ?: descriptorSize(location)
    }

    private fun columnSize(location: Uri): Long? {
        return try {
            context.contentResolver.query(
                location,
                arrayOf(OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                val column = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (column < 0 || !cursor.moveToFirst() || cursor.isNull(column)) {
                    null
                } else {
                    cursor.getLong(column)
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun descriptorSize(location: Uri): Long {
        return try {
            context.contentResolver.openAssetFileDescriptor(location, "r").use { descriptor ->
                descriptor?.length?.takeIf { it >= 0 } ?: 0L
            }
        } catch (_: Exception) {
            0L
        }
    }

    /**
     * Whether [location] already sits on removable storage.
     *
     * A SAF document id carries its volume in the same `volume:path` shape a
     * tree does — `primary:` for built-in storage, a card's uuid otherwise — so
     * [TreeLocation.parse] answers it without a volume lookup. Everything else
     * is built-in by construction: the app-private tier is internal storage, and
     * the gallery tier inserts into `EXTERNAL_CONTENT_URI`, which is the primary
     * volume.
     *
     * A `file:` path is checked against [StorageManager] all the same, because
     * `getStorageVolume` is the only thing that knows an adopted card — a card
     * formatted as internal storage, whose paths look nothing like a card's.
     */
    private fun isRemovable(location: Uri): Boolean {
        if (location.scheme == "file") return isRemovableFile(location)
        if (location.authority != EXTERNAL_STORAGE_PROVIDER) return false
        val documentId = try {
            DocumentsContract.getDocumentId(location)
        } catch (_: IllegalArgumentException) {
            return false
        }
        val parsed = TreeLocation.parse(documentId) ?: return false
        return !parsed.isPrimary
    }

    private fun isRemovableFile(location: Uri): Boolean {
        val path = location.path ?: return false
        return try {
            val volumes = context.getSystemService(StorageManager::class.java)
            volumes?.getStorageVolume(File(path))?.isRemovable == true
        } catch (_: Exception) {
            false
        }
    }

    private companion object {
        const val EXTERNAL_STORAGE_PROVIDER = "com.android.externalstorage.documents"
    }
}
