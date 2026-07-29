package cc.pym.tela

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.MediaStore
import java.io.File
import java.io.FileNotFoundException
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL

data class ImageStoreRequest(
    val source: String,
    val id: String,
    val imageUrl: String,
    val purity: String,
    val tier: String,
)

/**
 * A copy of an image **already on this device** into one of the three tiers.
 *
 * The local-source twin of [ImageStoreRequest]: same destination fields, but
 * the bytes come from [from] — a MediaStore URI, a SAF document, or a local
 * file — instead of the network. It is what lets a download change tier without
 * re-fetching several megabytes tela itself wrote.
 */
data class ImageCopyRequest(
    val source: String,
    val id: String,
    val from: String,
    val purity: String,
    val tier: String,
)

/**
 * One write into a tier: where it goes, what it is called, and where its bytes
 * come from.
 *
 * The seam that lets a download and a local copy share all three tier writers.
 * Everything those writers know is hard-won and specific — MediaStore
 * de-duplicating rather than overwriting, the `.nomedia` marker, `"wt"` to
 * truncate, and which failure paths may delete what they just created — and a
 * second copy of it to serve local sources is precisely where that knowledge
 * would rot. So the only thing that varies is [writeBytes].
 */
private class ImageWrite(
    val source: String,
    val id: String,
    val extension: String,
    val purity: String,
    val tier: String,
    val writeBytes: (OutputStream) -> Unit,
)

/** Android-only persistence boundary for tela's three image storage tiers. */
class ImageStorage(private val context: Context) {
    fun store(request: ImageStoreRequest, outsideGalleryTree: String?): Map<String, Any> {
        return write(
            ImageWrite(
                source = request.source,
                id = request.id,
                extension = urlExtension(request.imageUrl),
                purity = request.purity,
                tier = request.tier,
                writeBytes = { output -> copyRemote(request.imageUrl, output) },
            ),
            outsideGalleryTree,
        )
    }

    /**
     * Copies a file that is already on this device into [request]'s tier.
     *
     * Copies only — deleting the original is [deleteDownloads]' job, and the
     * two are kept apart so a caller can undo this when the user declines the
     * system delete prompt.
     *
     * The extension comes from the source's MIME type rather than from a URL,
     * because a `content://` URI has no suffix to read. It is load-bearing:
     * [listPrivate] drops any file whose name does not match [PRIVATE_FILE], so
     * a wrong extension would make a moved image silently vanish.
     */
    fun copy(request: ImageCopyRequest, outsideGalleryTree: String?): Map<String, Any> {
        val from = Uri.parse(request.from)
        return write(
            ImageWrite(
                source = request.source,
                id = request.id,
                extension = extensionOf(from),
                purity = request.purity,
                tier = request.tier,
                writeBytes = { output -> copyLocal(from, output) },
            ),
            outsideGalleryTree,
        )
    }

    /**
     * The purity/tier gate and the routing, shared by [store] and [copy].
     *
     * **This is the only place the NSFW rule is applied**, which is why a
     * caller that cannot prove an image is safe can hand it over as `nsfw` and
     * rely on the gallery becoming impossible rather than on remembering an
     * `if` of its own.
     */
    private fun write(request: ImageWrite, outsideGalleryTree: String?): Map<String, Any> {
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
     * [fileName] is derived from the wallpaper's source and id, so re-downloading
     * the same wallpaper always wants the same name — and `insert` does not overwrite,
     * it de-duplicates: MediaStore silently renames the second write to
     * `wallhaven-abc123 (1).jpg`. Downloading a wallpaper twice therefore left
     * the user with duplicates rather than one current file (owner, 2026-07-19).
     * Looking the row up first makes a re-download idempotent.
     */
    private fun storeInGallery(request: ImageWrite): Map<String, Any> {
        val existing = findGalleryImage(fileName(request))
        if (existing != null) return rewriteGalleryImage(existing, request)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName(request))
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType(request))
            put(MediaStore.MediaColumns.RELATIVE_PATH, TreeLocation.GALLERY_FOLDER_PATH)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: return failure("unavailable")
        return try {
            resolver.openOutputStream(uri)?.use { output -> request.writeBytes(output) }
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
    private fun rewriteGalleryImage(uri: Uri, request: ImageWrite): Map<String, Any> {
        val resolver = context.contentResolver
        // Hides the file from the gallery while it is half-written, the same
        // courtesy the insert path extends.
        resolver.update(uri, ContentValues().apply {
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }, null, null)
        return try {
            resolver.openOutputStream(uri, "wt")?.use { output ->
                request.writeBytes(output)
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
        val arguments = arrayOf("${TreeLocation.GALLERY_FOLDER_PATH}/", name)
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
        request: ImageWrite,
        outsideGalleryTree: String?,
    ): Map<String, Any> {
        val tree = outsideGalleryTree?.let(Uri::parse) ?: return failure("notConfigured")
        // Before anything is created: this tier writes a `.nomedia`, and a tree
        // that resolves onto the gallery's folder would hide it whole. A tree
        // tela cannot even read is refused as well — "is this somebody else's
        // directory" is not answerable there, and unanswerable is not no.
        if (TreeLocation.of(tree)?.overlapsGallery != false) {
            return failure("folderUnavailable")
        }
        val directory = outsideGalleryDirectory(tree) ?: return failure("unavailable")
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
            resolver.openOutputStream(file)?.use { output -> request.writeBytes(output) }
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
    private fun rewriteDocument(file: Uri, request: ImageWrite): Map<String, Any> {
        context.contentResolver.openOutputStream(file, "wt")?.use { output ->
            request.writeBytes(output)
        } ?: throw IllegalStateException("document output stream was null")
        return success(file)
    }

    private fun storePrivately(request: ImageWrite): Map<String, Any> {
        val directory = privateDirectory()
        if (!ensureDirectory(directory)) return failure("unavailable")
        val file = File(directory, fileName(request))
        file.outputStream().use { output -> request.writeBytes(output) }
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
                val key = keyOf(file.name) ?: return@mapNotNull null
                val (width, height) = pixelBounds(file)
                mapOf(
                    "ref" to key,
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
     * Deletes one app-private image, named by its `source-id` [key].
     *
     * The key is matched against [VALID_KEY] before it is used to build any
     * path. It arrives over a method channel, and a key like
     * `../../databases/tela` is how a listing feature becomes an
     * arbitrary-file-delete.
     *
     * Source-qualified so that two sources issuing the same number cannot
     * delete each other's file — the reason `WallpaperRef` exists on the Dart
     * side, applied to the one tier whose identity lives in a file name.
     */
    /**
     * **A file that is already gone counts as deleted**, and answering
     * `unavailable` for one is the bug this used to have. See
     * [deleteDocumentAt] for the whole argument; it is the same rule, and the
     * empty match list here is exactly the "already gone" case.
     */
    fun deletePrivate(key: String): Map<String, Any> {
        if (!VALID_KEY.matches(key)) return failure("unavailable")
        val matches = privateDirectory()
            .listFiles()
            ?.filter { it.isFile && keyOf(it.name) == key }
            ?: emptyList()
        if (matches.isEmpty()) return mapOf("success" to true)
        if (!matches.all { it.delete() }) return failure("unavailable")
        return mapOf("success" to true)
    }

    /**
     * Hard-deletes a downloaded file from its [tier] — the file, not an index.
     *
     * The gallery tier on API 30+ is deliberately **not** here: it needs an
     * Activity to launch `MediaStore.createDeleteRequest`, which MainActivity
     * owns. This handles the app-private file, the SAF document, and the direct
     * gallery delete the older API (29) still permits. appPrivate reuses the
     * guarded [deletePrivate] by recovering the id from the file's own name.
     */
    fun deleteDownload(tier: String, location: Uri): Map<String, Any> {
        return when (tier) {
            "appPrivate" -> deletePrivateAt(location)
            "filesOutsideGallery" -> deleteDocumentAt(location)
            "sharedGallery" -> deleteGalleryDirectly(location)
            else -> failure("unavailable")
        }
    }

    /** Recovers the key from the private file's name so [deletePrivate]'s listing
     *  guard still stands — a location is a `file:` URI tela itself wrote. */
    private fun deletePrivateAt(location: Uri): Map<String, Any> {
        val key = location.lastPathSegment?.let(::keyOf) ?: return failure("unavailable")
        val result = deletePrivate(key)
        return if (result["success"] == true) deleted(location) else result
    }

    /**
     * Deletes the SAF document tela created under the user's granted tree.
     *
     * **A document that is already gone counts as deleted**, because it is: the
     * end state the user asked for has been reached by other means. This is the
     * same decision `MainActivity.planDeletions` records for the gallery tier —
     * it was made on 2026-07-28 and applied only there, because there a stale
     * row *crashed* and here it merely failed in silence.
     *
     * Silence is its own trap. `DeleteDownloads` forgets only the rows whose
     * files came back deleted, so a `filesOutsideGallery` row whose file went
     * away behind tela's back — deleted from a file manager, over USB, by a
     * storage cleaner, or on a card that was unmounted — could **never be
     * removed from download history**. The user selects it, taps delete, and
     * nothing happens, with no error to explain why. Reported by the owner,
     * 2026-07-28, against a history full of rows whose files had been removed
     * out of band.
     *
     * Checked *after* the delete rather than before it, unlike the gallery
     * tier's up-front `galleryRowExists`. There the check exists because
     * `createDeleteRequest` throws on a stale row and had to never see one;
     * nothing here throws, so the happy path pays nothing.
     *
     * **`FileNotFoundException` is answered without a second question**, and
     * that is a cost decision, not a tidiness one. It is what the storage
     * provider raises for a document that is not there, so it *is* the "already
     * gone" answer — and clearing a history of hundreds of stale rows is
     * exactly when this path runs hundreds of times. Paying a delete and then a
     * query for every one of them doubled the binder traffic of the slowest
     * thing the screen does (owner, 2026-07-28: "taking too long when we have
     * too many images"). Only a provider that reports failure *without* saying
     * why still gets asked.
     */
    private fun deleteDocumentAt(location: Uri): Map<String, Any> {
        val removed = try {
            DocumentsContract.deleteDocument(context.contentResolver, location)
        } catch (_: FileNotFoundException) {
            return deleted(location)
        } catch (_: Exception) {
            false
        }
        if (removed || !documentExists(location)) return deleted(location)
        return failure("unavailable")
    }

    /**
     * Whether the granted tree still holds a document at [location].
     *
     * Asked only when a delete has already failed, to tell "it was not there"
     * from "it would not go" — the provider reports both as false, and one of
     * them is the user's request already satisfied. A revoked grant or an
     * ejected card answers false too, and that is the right answer: tela cannot
     * reach the file, and holding an unclearable history row for it helps
     * nobody.
     */
    private fun documentExists(location: Uri): Boolean {
        val projection = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
        return try {
            context.contentResolver
                .query(location, projection, null, null, null)
                ?.use { cursor -> cursor.moveToFirst() } ?: false
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Deletes a MediaStore image directly — API 29 only.
     *
     * On 30+ this throws `RecoverableSecurityException` and the caller never
     * routes here; MainActivity launches the system delete request instead.
     */
    private fun deleteGalleryDirectly(location: Uri): Map<String, Any> {
        val removed = context.contentResolver.delete(location, null, null)
        return if (removed > 0) deleted(location) else failure("unavailable")
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
        if (!ensureDirectory(directory)) return mapOf("success" to false)
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

    /**
     * Recovers the `source-id` key from a file tela itself wrote, or null.
     *
     * The key, not the bare id: the private tier writes no database row (an
     * explicit download is deliberately absent from the history), so the file
     * name is the *only* place a private image's source survives. Two sources
     * can issue the same id — Konachan #12345 and yande.re #12345 — so a bare
     * id is not an identity here.
     *
     * Files written before the source-qualified name (2026-07-26) parse
     * unchanged: every one of them is Wallhaven's, and the prefix they already
     * carry is `wallhaven`. Konachan files written between its arrival and this
     * change are the one exception and read back as Wallhaven; re-downloading
     * one corrects it.
     */
    private fun keyOf(fileName: String): String? {
        val match = PRIVATE_FILE.matchEntire(fileName) ?: return null
        return "${match.groupValues[1]}-${match.groupValues[2]}"
    }

    private fun outsideGalleryDirectory(tree: Uri): Uri? {
        if (tree.authority != EXTERNAL_STORAGE_PROVIDER) return null
        val root = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        return findOrCreateDirectory(root, TreeLocation.TELA_FOLDER)
    }

    /**
     * Whether MediaStore still has a row at [location].
     *
     * Asked before a gallery delete, and deliberately **not** [canRead]: a row
     * can outlive its file, and such a row is still perfectly deletable. Only the
     * row's existence decides whether `MediaStore.createDeleteRequest` will
     * accept it — see `MainActivity.planDeletions` for why a stale one may never
     * reach it.
     */
    fun galleryRowExists(location: Uri): Boolean {
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        return try {
            context.contentResolver
                .query(location, projection, null, null, null)
                ?.use { cursor -> cursor.moveToFirst() } ?: false
        } catch (_: Exception) {
            false
        }
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

    /**
     * Makes sure [directory] exists, tolerating another thread creating it first.
     *
     * The obvious `!exists() && !mkdirs()` is **not** thread-safe, and stopped
     * being merely theoretical when downloads moved onto a thread pool
     * (`MainActivity.downloadExecutor`): two concurrent stores both see the
     * directory missing, both call `mkdirs`, and the loser gets `false` for a
     * directory that now exists — so a perfectly good download reported
     * `unavailable` and wrote nothing. Found by `ConcurrentDownloadTest`.
     *
     * What matters is the state afterwards, not who created it.
     */
    private fun ensureDirectory(directory: File): Boolean {
        directory.mkdirs()
        return directory.isDirectory
    }

    /**
     * Streams a file already on this device into [output].
     *
     * Goes through the ContentResolver, which is what makes one function cover
     * all three tiers: a MediaStore image, a SAF document and a `file:` URI all
     * open the same way.
     */
    private fun copyLocal(from: Uri, output: OutputStream) {
        context.contentResolver.openInputStream(from)?.use { input ->
            input.copyTo(output)
        } ?: throw IllegalStateException("no input stream for the stored image")
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

    /**
     * The name a downloaded file takes on disk: `source-id.ext`.
     *
     * The source prefix is not decoration. It is what makes the app-private
     * tier's listing able to say where an image came from, and it was a
     * hardcoded `wallhaven-` until 2026-07-26 — which silently filed every
     * Konachan download under Wallhaven's name in all three tiers.
     *
     * Both halves are matched against their allowlists before either reaches a
     * path. `require` rather than a returned failure: Dart composes these from
     * a `SourceId` and a wallpaper's own id, so a bad shape here is a caller
     * bug, not a condition the user can be in.
     */
    private fun fileName(request: ImageWrite): String {
        require(VALID_SOURCE.matches(request.source)) { "source id has an invalid shape" }
        require(VALID_ID.matches(request.id)) { "wallpaper id has an invalid shape" }
        return "${request.source}-${request.id}.${request.extension}"
    }

    private fun urlExtension(imageUrl: String): String {
        return when {
            imageUrl.substringBefore('?').endsWith(".png", true) -> "png"
            imageUrl.substringBefore('?').endsWith(".webp", true) -> "webp"
            imageUrl.substringBefore('?').endsWith(".jpeg", true) -> "jpeg"
            else -> "jpg"
        }
    }

    /**
     * The extension for a file already on this device.
     *
     * A `content://` URI carries no suffix to read, so the MIME type the
     * resolver reports is asked first; a `file:` URI answers null there and
     * falls back to its own suffix. `jpg` is the last resort, matching
     * [urlExtension] — an unknown type is far likelier to be a JPEG than to be
     * worth refusing the move over.
     *
     * Only the four [PRIVATE_FILE] accepts are ever returned: anything else
     * would make a copy into the private tier unlistable, which reads to the
     * user as the image having vanished.
     */
    private fun extensionOf(from: Uri): String {
        val mime = context.contentResolver.getType(from)
        return when {
            mime != null -> mimeExtension(mime)
            else -> urlExtension(from.lastPathSegment.orEmpty())
        }
    }

    private fun mimeExtension(mime: String): String {
        return when (mime.substringBefore(';').trim().lowercase()) {
            "image/png" -> "png"
            "image/webp" -> "webp"
            else -> "jpg"
        }
    }

    private fun mimeType(request: ImageWrite): String {
        return when (request.extension) {
            "png" -> "image/png"
            "webp" -> "image/webp"
            else -> "image/jpeg"
        }
    }

    private fun success(location: Uri): Map<String, Any> = mapOf(
        "success" to true,
        "location" to location.toString(),
    )

    /**
     * A completed hard delete, reporting the location that went.
     *
     * The `deleted` list is the shape the single and bulk deletes share, so Dart
     * reads one contract: a single delete is the one-item case of the batch one.
     */
    private fun deleted(location: Uri): Map<String, Any> = mapOf(
        "success" to true,
        "deleted" to listOf(location.toString()),
    )

    private fun failure(code: String): Map<String, Any> = mapOf(
        "success" to false,
        "errorCode" to code,
    )

    private companion object {
        const val EXTERNAL_STORAGE_PROVIDER = "com.android.externalstorage.documents"
        const val NETWORK_TIMEOUT_MS = 30_000
        /**
         * A wallpaper id, as its own source issued it.
         *
         * `-` is deliberately **not** here, though it was until 2026-07-26: a
         * file is now named `source-id`, and a hyphen on either side of that
         * join would make the split ambiguous. No source issues one — Wallhaven's
         * ids are lowercase alphanumeric and a booru's are digits — so this
         * narrows an allowlist without narrowing what tela can store.
         */
        val VALID_ID = Regex("[A-Za-z0-9_]{1,64}")

        /** Mirrors Dart's `SourceId` shape, which is what composes these names. */
        val VALID_SOURCE = Regex("[a-z0-9_]{1,32}")

        /** The `source-id` pair as one string, the form [deletePrivate] takes. */
        val VALID_KEY = Regex("[a-z0-9_]{1,32}-[A-Za-z0-9_]{1,64}")

        /**
         * Matches only the names tela writes, capturing the source and the id.
         *
         * Old `wallhaven-*` files need no migration: they are all Wallhaven's,
         * and group 1 reads back exactly that.
         */
        val PRIVATE_FILE =
            Regex("([a-z0-9_]{1,32})-([A-Za-z0-9_]{1,64})\\.(jpg|jpeg|png|webp)")
        val SUPPORTED_PURITIES = setOf("sfw", "sketchy", "nsfw")
        val SUPPORTED_TIERS = setOf("sharedGallery", "filesOutsideGallery", "appPrivate")
    }
}
