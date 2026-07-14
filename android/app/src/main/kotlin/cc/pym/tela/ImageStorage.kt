package cc.pym.tela

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import java.io.File
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL

data class ImageStoreRequest(
    val id: String,
    val imageUrl: String,
    val purity: String,
    val tier: String,
)

/** Android-only persistence boundary for tela's three image storage tiers. */
class ImageStorage(private val context: Context) {
    fun store(request: ImageStoreRequest, outsideGalleryTree: String?): Map<String, Any> {
        if (request.purity !in SUPPORTED_PURITIES || request.tier !in SUPPORTED_TIERS) {
            return failure("unavailable")
        }
        if (request.purity == "nsfw" && request.tier == "sharedGallery") {
            return failure("restricted")
        }
        return try {
            when (request.tier) {
                "sharedGallery" -> storeInGallery(request)
                "filesOutsideGallery" -> storeOutsideGallery(request, outsideGalleryTree)
                "appPrivate" -> storePrivately(request)
                else -> failure("unavailable")
            }
        } catch (_: Exception) {
            failure("downloadFailed")
        }
    }

    private fun storeInGallery(request: ImageStoreRequest): Map<String, Any> {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName(request))
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType(request))
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/tela")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: return failure("unavailable")
        return try {
            resolver.openOutputStream(uri)?.use { output -> copyRemote(request.imageUrl, output) }
                ?: throw IllegalStateException("MediaStore output stream was null")
            resolver.update(uri, ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }, null, null)
            success(uri)
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    private fun storeOutsideGallery(
        request: ImageStoreRequest,
        outsideGalleryTree: String?,
    ): Map<String, Any> {
        val tree = outsideGalleryTree ?: return failure("notConfigured")
        val directory = outsideGalleryDirectory(Uri.parse(tree))
            ?: return failure("unavailable")
        if (!ensureNoMediaMarker(directory)) return failure("unavailable")
        val resolver = context.contentResolver
        val file = DocumentsContract.createDocument(
            resolver,
            directory,
            mimeType(request),
            fileName(request),
        ) ?: return failure("unavailable")
        return try {
            resolver.openOutputStream(file)?.use { output -> copyRemote(request.imageUrl, output) }
                ?: throw IllegalStateException("document output stream was null")
            success(file)
        } catch (error: Exception) {
            resolver.delete(file, null, null)
            throw error
        }
    }

    private fun storePrivately(request: ImageStoreRequest): Map<String, Any> {
        val directory = privateDirectory()
        if (!directory.exists() && !directory.mkdirs()) return failure("unavailable")
        val file = File(directory, fileName(request))
        file.outputStream().use { output -> copyRemote(request.imageUrl, output) }
        return success(Uri.fromFile(file))
    }

    /**
     * Lists the app-private tier, newest first.
     *
     * Only this tier is listable: the other two land where the system gallery or
     * a file manager already shows them. These files are visible to nothing but
     * tela, so without this they can only be written, never seen.
     */
    fun listPrivate(): Map<String, Any> {
        val files = privateDirectory().listFiles()?.filter { it.isFile } ?: emptyList()
        val images = files
            .sortedByDescending { it.lastModified() }
            .mapNotNull { file ->
                val id = idOf(file.name) ?: return@mapNotNull null
                mapOf(
                    "id" to id,
                    "location" to Uri.fromFile(file).toString(),
                    "savedAt" to file.lastModified(),
                    "sizeBytes" to file.length(),
                )
            }
        return mapOf("success" to true, "images" to images)
    }

    /**
     * Deletes one app-private image.
     *
     * The id is matched against [VALID_ID] before it is used to build any path.
     * It arrives over a method channel, and an id like `../../databases/tela` is
     * how a listing feature becomes an arbitrary-file-delete.
     */
    fun deletePrivate(id: String): Map<String, Any> {
        if (!VALID_ID.matches(id)) return failure("unavailable")
        val matches = privateDirectory()
            .listFiles()
            ?.filter { it.isFile && idOf(it.name) == id }
            ?: emptyList()
        if (matches.isEmpty()) return failure("unavailable")
        if (!matches.all { it.delete() }) return failure("unavailable")
        return mapOf("success" to true)
    }

    private fun privateDirectory(): File = File(context.filesDir, "wallpapers")

    /** Recovers the Wallhaven id from a file tela itself wrote, or null. */
    private fun idOf(fileName: String): String? =
        PRIVATE_FILE.matchEntire(fileName)?.groupValues?.get(1)

    private fun outsideGalleryDirectory(tree: Uri): Uri? {
        if (tree.authority != EXTERNAL_STORAGE_PROVIDER) return null
        val root = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        return findOrCreateDirectory(root, "tela")
    }

    private fun ensureNoMediaMarker(directory: Uri): Boolean {
        if (findChild(directory, ".nomedia") != null) return true
        return DocumentsContract.createDocument(
            context.contentResolver,
            directory,
            "application/octet-stream",
            ".nomedia",
        ) != null
    }

    private fun findOrCreateDirectory(parent: Uri, name: String): Uri? {
        return findChild(parent, name) ?: DocumentsContract.createDocument(
            context.contentResolver,
            parent,
            DocumentsContract.Document.MIME_TYPE_DIR,
            name,
        )
    }

    private fun findChild(parent: Uri, name: String): Uri? {
        val resolver = context.contentResolver
        val childDocuments = DocumentsContract.buildChildDocumentsUriUsingTree(
            parent,
            DocumentsContract.getDocumentId(parent),
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        )
        resolver.query(childDocuments, projection, null, null, null)?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            )
            val nameColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            )
            while (cursor.moveToNext()) {
                if (cursor.getString(nameColumn) == name) {
                    return DocumentsContract.buildDocumentUriUsingTree(
                        parent,
                        cursor.getString(idColumn),
                    )
                }
            }
        }
        return null
    }

    private fun copyRemote(imageUrl: String, output: OutputStream) {
        val connection = URL(imageUrl).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = NETWORK_TIMEOUT_MS
            connection.readTimeout = NETWORK_TIMEOUT_MS
            connection.instanceFollowRedirects = true
            if (connection.responseCode !in 200..299) {
                throw IllegalStateException("remote image returned a non-success status")
            }
            connection.inputStream.use { input -> input.copyTo(output) }
        } finally {
            connection.disconnect()
        }
    }

    private fun fileName(request: ImageStoreRequest): String {
        require(VALID_ID.matches(request.id)) { "wallpaper id has an invalid shape" }
        return "wallhaven-${request.id}.${imageExtension(request.imageUrl)}"
    }

    private fun imageExtension(imageUrl: String): String {
        return when {
            imageUrl.substringBefore('?').endsWith(".png", true) -> "png"
            imageUrl.substringBefore('?').endsWith(".webp", true) -> "webp"
            imageUrl.substringBefore('?').endsWith(".jpeg", true) -> "jpeg"
            else -> "jpg"
        }
    }

    private fun mimeType(request: ImageStoreRequest): String {
        return when (imageExtension(request.imageUrl)) {
            "png" -> "image/png"
            "webp" -> "image/webp"
            else -> "image/jpeg"
        }
    }

    private fun success(location: Uri): Map<String, Any> = mapOf(
        "success" to true,
        "location" to location.toString(),
    )

    private fun failure(code: String): Map<String, Any> = mapOf(
        "success" to false,
        "errorCode" to code,
    )

    private companion object {
        const val EXTERNAL_STORAGE_PROVIDER = "com.android.externalstorage.documents"
        const val NETWORK_TIMEOUT_MS = 30_000
        val VALID_ID = Regex("[A-Za-z0-9_-]{1,64}")

        /** Matches only the names tela writes, and captures the id back out. */
        val PRIVATE_FILE = Regex("wallhaven-([A-Za-z0-9_-]{1,64})\\.(jpg|jpeg|png|webp)")
        val SUPPORTED_PURITIES = setOf("sfw", "sketchy", "nsfw")
        val SUPPORTED_TIERS = setOf("sharedGallery", "filesOutsideGallery", "appPrivate")
    }
}
