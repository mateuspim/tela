package cc.pym.tela

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.graphics.BitmapFactory
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

    /**
     * Writes into the gallery, **reusing the row this wallpaper already owns**.
     *
     * [fileName] is derived from the Wallhaven id, so re-downloading the same
     * wallpaper always wants the same name — and `insert` does not overwrite,
     * it de-duplicates: MediaStore silently renames the second write to
     * `wallhaven-abc123 (1).jpg`. Downloading a wallpaper twice therefore left
     * the user with duplicates rather than one current file (owner, 2026-07-19).
     * Looking the row up first makes a re-download idempotent.
     */
    private fun storeInGallery(request: ImageStoreRequest): Map<String, Any> {
        val existing = findGalleryImage(fileName(request))
        if (existing != null) return rewriteGalleryImage(existing, request)
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
            markReady(uri)
            success(uri)
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    /**
     * Overwrites the file already at [uri], in place.
     *
     * Two things here are load-bearing:
     *
     * - The stream is opened `"wt"`, not the default `"w"`. Plain write does not
     *   truncate, so replacing a large image with a smaller one would leave the
     *   tail of the old file behind and produce a corrupt image.
     * - A failure **must not delete [uri]**, unlike the insert path above. That
     *   path removes a row it created moments earlier; this one would be
     *   destroying a file the user already had, to no purpose — a failed
     *   re-download should leave the existing copy exactly where it was.
     */
    private fun rewriteGalleryImage(uri: Uri, request: ImageStoreRequest): Map<String, Any> {
        val resolver = context.contentResolver
        // Hides the file from the gallery while it is half-written, the same
        // courtesy the insert path extends.
        resolver.update(uri, ContentValues().apply {
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }, null, null)
        return try {
            resolver.openOutputStream(uri, "wt")?.use { output ->
                copyRemote(request.imageUrl, output)
            } ?: throw IllegalStateException("MediaStore output stream was null")
            markReady(uri)
            success(uri)
        } catch (error: Exception) {
            markReady(uri)
            throw error
        }
    }

    private fun markReady(uri: Uri) {
        context.contentResolver.update(uri, ContentValues().apply {
            put(MediaStore.MediaColumns.IS_PENDING, 0)
        }, null, null)
    }

    /**
     * The row tela already wrote for [name] under `Pictures/tela`, if any.
     *
     * Scoped to that directory as well as the name: another app's
     * `wallhaven-abc123.jpg` elsewhere on the device is not ours to overwrite.
     * MediaStore stores `RELATIVE_PATH` with a trailing separator, so the
     * comparison carries one.
     */
    private fun findGalleryImage(name: String): Uri? {
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection = "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND " +
            "${MediaStore.MediaColumns.DISPLAY_NAME}=?"
        val arguments = arrayOf("${Environment.DIRECTORY_PICTURES}/tela/", name)
        context.contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            arguments,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID))
                return ContentUris.withAppendedId(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    id,
                )
            }
        }
        return null
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
        // Same duplicate trap as the gallery tier, through a different door:
        // `createDocument` also renames rather than replacing, so a second
        // download of one wallpaper produced `wallhaven-abc123 (1).jpg`. This is
        // the desktop-sync path, where a directory quietly accumulating near
        // copies of every wallpaper is worse still.
        val existing = findChild(directory, fileName(request))
        if (existing != null) return rewriteDocument(existing, request)
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

    /**
     * Overwrites an existing document in place, truncating it first.
     *
     * `"wt"` and the absence of a delete-on-failure are load-bearing for the
     * same reasons [rewriteGalleryImage] gives.
     */
    private fun rewriteDocument(file: Uri, request: ImageStoreRequest): Map<String, Any> {
        context.contentResolver.openOutputStream(file, "wt")?.use { output ->
            copyRemote(request.imageUrl, output)
        } ?: throw IllegalStateException("document output stream was null")
        return success(file)
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
                val (width, height) = pixelBounds(file)
                mapOf(
                    "id" to id,
                    "location" to Uri.fromFile(file).toString(),
                    "savedAt" to file.lastModified(),
                    "sizeBytes" to file.length(),
                    "width" to width,
                    "height" to height,
                )
            }
        return mapOf("success" to true, "images" to images)
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
        val directory = previewDirectory()
        if (!directory.exists() && !directory.mkdirs()) return mapOf("success" to false)
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
     * [previewDirectory] before anything is deleted — the same shape of guard
     * as [deletePrivate]'s id check, so a preview release can never become an
     * arbitrary-file delete.
     */
    fun releasePreview(path: String): Map<String, Any> {
        val file = File(path)
        val root = previewDirectory()
        val within = try {
            file.canonicalPath.startsWith(root.canonicalPath + File.separator)
        } catch (_: Exception) {
            false
        }
        if (within && file.isFile) file.delete()
        return mapOf("success" to true)
    }

    private fun previewDirectory(): File = File(context.cacheDir, "previews")

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
