package cc.pym.tela

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.MediaStore
import java.io.File
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL

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
    val tag: String?,
    val writeBytes: (OutputStream) -> Unit,
) {
    val fileName: String get() = ImageFileNaming.fileName(source, id, extension)
    val mimeType: String get() = ImageFileNaming.mimeType(extension)
}

/**
 * Writing an image into one of tela's three storage tiers.
 *
 * Holds the purity gate every write passes through and the three tier writers
 * it routes to. [TierDeleting] is its counterpart; the two are apart because a
 * write that succeeded and a delete that could not are different stories.
 *
 * ```
 * TierWriting(context).store(request, outsideGalleryTree)
 * ```
 */
internal class TierWriting(private val context: Context) {
    /** Downloads [request]'s image from the network into its tier. */
    fun store(request: ImageStoreRequest, outsideGalleryTree: String?): Map<String, Any> {
        return write(
            ImageWrite(
                source = request.source,
                id = request.id,
                extension = ImageFileNaming.urlExtension(request.imageUrl),
                purity = request.purity,
                tier = request.tier,
                tag = request.tag,
                writeBytes = { output -> copyRemote(request.imageUrl, output) },
            ),
            outsideGalleryTree,
        )
    }

    /**
     * Copies a file that is already on this device into [request]'s tier.
     *
     * Copies only — deleting the original is [TierDeleting.deleteDownload]'s
     * job, and the two are kept apart so a caller can undo this when the user
     * declines the system delete prompt.
     *
     * The extension comes from the source's MIME type rather than from a URL,
     * because a `content://` URI has no suffix to read. It is load-bearing:
     * [PrivateTierListing] drops any file whose name does not parse, so a wrong
     * extension would make a moved image silently vanish.
     */
    fun copy(request: ImageCopyRequest, outsideGalleryTree: String?): Map<String, Any> {
        val from = Uri.parse(request.from)
        return write(
            ImageWrite(
                source = request.source,
                id = request.id,
                extension = ImageFileNaming.extensionOf(context, from),
                purity = request.purity,
                tier = request.tier,
                tag = request.tag,
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
     *
     * The tag is checked **after** the purity rule and before any routing. After,
     * so a request that is both explicit-into-the-gallery and badly tagged still
     * reports `restricted` — the invariant's own answer must not be masked by an
     * argument complaint. Before routing, because from here on the tag is a path
     * segment, and the three writers must never be the ones deciding whether it
     * was safe to be one.
     */
    private fun write(request: ImageWrite, outsideGalleryTree: String?): Map<String, Any> {
        if (request.purity !in SUPPORTED_PURITIES || request.tier !in SUPPORTED_TIERS) {
            return imageStoreFailure("unavailable")
        }
        if (request.purity == "nsfw" && request.tier == "sharedGallery") {
            return imageStoreFailure("restricted")
        }
        val tag = request.tag
        if (tag != null && !TagFolders.isValid(tag)) return imageStoreFailure("unavailable")
        return try {
            when (request.tier) {
                "sharedGallery" -> storeInGallery(request)
                "filesOutsideGallery" -> storeOutsideGallery(request, outsideGalleryTree)
                "appPrivate" -> storePrivately(request)
                else -> imageStoreFailure("unavailable")
            }
        } catch (_: Exception) {
            imageStoreFailure("downloadFailed")
        }
    }

    /**
     * Writes into the gallery, **reusing the row this wallpaper already owns**.
     *
     * The file name is derived from the wallpaper's source and id, so
     * re-downloading the same wallpaper always wants the same name — and
     * `insert` does not overwrite, it de-duplicates: MediaStore silently renames
     * the second write to `wallhaven-abc123 (1).jpg`. Downloading a wallpaper
     * twice therefore left the user with duplicates rather than one current file
     * (owner, 2026-07-19). Looking the row up first makes a re-download
     * idempotent.
     */
    private fun storeInGallery(request: ImageWrite): Map<String, Any> {
        val folder = TagFolders.galleryPath(request.tag)
        val existing = findGalleryImage(request.fileName, folder)
        if (existing != null) return rewriteGalleryImage(existing, request)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, request.fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, request.mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: return imageStoreFailure("unavailable")
        return try {
            resolver.openOutputStream(uri)?.use { output -> request.writeBytes(output) }
                ?: throw IllegalStateException("MediaStore output stream was null")
            markReady(uri)
            stored(uri)
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
            stored(uri)
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
     * The row tela already wrote for [name] under [folder], if any.
     *
     * Scoped to that directory as well as the name: another app's
     * `wallhaven-abc123.jpg` elsewhere on the device is not ours to overwrite.
     * MediaStore stores `RELATIVE_PATH` with a trailing separator, so the
     * comparison carries one.
     *
     * [folder] is a parameter rather than the constant it used to be because a
     * tag *is* a directory: `Pictures/tela/anime` and `Pictures/tela/minimal`
     * hold different files, and a lookup that ignored the tag would rewrite one
     * tag's copy while the caller believed it was writing another's.
     */
    private fun findGalleryImage(name: String, folder: String): Uri? {
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection = "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND " +
            "${MediaStore.MediaColumns.DISPLAY_NAME}=?"
        val arguments = arrayOf("$folder/", name)
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
        val tree = outsideGalleryTree?.let(Uri::parse) ?: return imageStoreFailure("notConfigured")
        // Before anything is created: this tier writes a `.nomedia`, and a tree
        // that resolves onto the gallery's folder would hide it whole. A tree
        // tela cannot even read is refused as well — "is this somebody else's
        // directory" is not answerable there, and unanswerable is not no.
        if (TreeLocation.of(tree)?.overlapsGallery != false) {
            return imageStoreFailure("folderUnavailable")
        }
        val telaFolder = SafDocuments.telaFolderIn(context, tree)
            ?: return imageStoreFailure("unavailable")
        if (!SafDocuments.ensureNoMediaMarker(context, telaFolder)) {
            return imageStoreFailure("unavailable")
        }
        // The tag's own folder is marked too. A `.nomedia` in the parent already
        // covers the subtree for Android's scanner, so this is belt and braces —
        // but this tier's entire contract is "not in the gallery index", the
        // marker costs one document, and a subtree exclusion is a scanner
        // behaviour rather than a documented guarantee. See `TreeLocation`, which
        // records what a mis-marked directory cost the owner once already.
        val directory = SafDocuments.tagFolderIn(context, telaFolder, request.tag)
            ?: return imageStoreFailure("unavailable")
        if (directory != telaFolder && !SafDocuments.ensureNoMediaMarker(context, directory)) {
            return imageStoreFailure("unavailable")
        }
        val resolver = context.contentResolver
        // Same duplicate trap as the gallery tier, through a different door:
        // `createDocument` also renames rather than replacing, so a second
        // download of one wallpaper produced `wallhaven-abc123 (1).jpg`. This is
        // the desktop-sync path, where a directory quietly accumulating near
        // copies of every wallpaper is worse still.
        val existing = SafDocuments.findChild(context, directory, request.fileName)
        if (existing != null) return rewriteDocument(existing, request)
        val file = DocumentsContract.createDocument(
            resolver,
            directory,
            request.mimeType,
            request.fileName,
        ) ?: return imageStoreFailure("unavailable")
        return try {
            resolver.openOutputStream(file)?.use { output -> request.writeBytes(output) }
                ?: throw IllegalStateException("document output stream was null")
            stored(file)
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
        return stored(file)
    }

    private fun storePrivately(request: ImageWrite): Map<String, Any> {
        val directory = TagFolders.privateDirectory(context, request.tag)
            ?: return imageStoreFailure("unavailable")
        if (!TelaDirectories.ensure(directory)) return imageStoreFailure("unavailable")
        val file = File(directory, request.fileName)
        file.outputStream().use { output -> request.writeBytes(output) }
        return stored(Uri.fromFile(file))
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

    private fun stored(location: Uri): Map<String, Any> = mapOf(
        "success" to true,
        "location" to location.toString(),
    )

    private companion object {
        const val NETWORK_TIMEOUT_MS = 30_000
        val SUPPORTED_PURITIES = setOf("sfw", "sketchy", "nsfw")
        val SUPPORTED_TIERS = setOf("sharedGallery", "filesOutsideGallery", "appPrivate")
    }
}
