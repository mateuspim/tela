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
    val localCopyFrom: Uri? = null,
    val expectedDigest: (() -> StreamDigest?)? = null,
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
 * The gate has **two** consequences, not one, and both are here rather than in
 * any caller: an explicit image can never reach the gallery, and on the files
 * tier it lands in the hidden vault rather than the visible folder. See
 * [rootFor].
 *
 * ```
 * TierWriting(context).store(request, OutsideGalleryTarget(tree, "tela"))
 * ```
 */
internal class TierWriting(private val context: Context) {
    private val localCopies = LocalCopyChecks(context)

    /** Downloads [request]'s image from the network into its tier. */
    fun store(request: ImageStoreRequest, target: OutsideGalleryTarget): Map<String, Any> {
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
            target,
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
    fun copy(request: ImageCopyRequest, target: OutsideGalleryTarget): Map<String, Any> {
        val from = Uri.parse(request.from)
        var copiedDigest: StreamDigest? = null
        return write(
            ImageWrite(
                source = request.source,
                id = request.id,
                extension = ImageFileNaming.extensionOf(context, from),
                purity = request.purity,
                tier = request.tier,
                tag = request.tag,
                localCopyFrom = from,
                expectedDigest = { copiedDigest },
                writeBytes = { output -> copiedDigest = copyLocal(from, output) },
            ),
            target,
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
    private fun write(request: ImageWrite, target: OutsideGalleryTarget): Map<String, Any> {
        val result = attempt(request, target)
        // Every refusal, not just the thrown ones. Most of the ways this fails
        // are an ordinary `return imageStoreFailure(...)` — a missing tree, a
        // folder that could not be made — and logging only the exceptions left
        // the common half of the failures as silent as before (owner,
        // 2026-08-25).
        if (result["success"] != true) {
            TierWriteLog.refusal(request.tier, request.purity, result["errorCode"] as? String)
        }
        return result
    }

    private fun attempt(request: ImageWrite, target: OutsideGalleryTarget): Map<String, Any> {
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
                "filesOutsideGallery" -> storeOutsideGallery(request, target)
                "appPrivate" -> storePrivately(request)
                else -> imageStoreFailure("unavailable")
            }
        } catch (error: Exception) {
            // Logged, not rethrown: a failed write is an ordinary outcome for
            // the caller. What was missing was any way to tell *which* failure
            // it was — see [TierWriteLog].
            TierWriteLog.failure(request.tier, request.purity, error)
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
        val result = existing
            ?.let { uri -> rewriteGalleryImage(uri, request) }
            ?: insertGalleryImage(request, folder)
        if (result["success"] == true) dropOtherGalleryTags(request)
        return result
    }

    private fun insertGalleryImage(request: ImageWrite, folder: String): Map<String, Any> {
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
            stored(uri, request.tag)
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    /**
     * Deletes this wallpaper's rows under other tag folders — one wallpaper, one
     * tag, as [dropOtherPrivateTags] argues in full.
     *
     * **A copy that will not delete is left alone rather than retried.** Media
     * ownership is per install, so a file written before the 2026-08-11
     * reinstall belongs to nobody as far as this package is concerned and needs
     * the user's confirmation to remove — a prompt that cannot be raised here,
     * because a queued download drains with no screen attached. One visible
     * duplicate the user can delete beats a download that fails, or a prompt
     * that never appears.
     */
    private fun dropOtherGalleryTags(request: ImageWrite) {
        val selection = "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND " +
            "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ? AND " +
            "${MediaStore.MediaColumns.RELATIVE_PATH}!=?"
        val arguments = arrayOf(
            request.fileName,
            "${TreeLocation.GALLERY_FOLDER_PATH}/%",
            "${TagFolders.galleryPath(request.tag)}/",
        )
        try {
            context.contentResolver.delete(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                selection,
                arguments,
            )
        } catch (_: Exception) {
            // See the docstring: an undeletable older copy is not this
            // download's problem to fail over.
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
            stored(uri, request.tag)
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

    /**
     * Which root inside the granted tree this image belongs in: the visible
     * `tela/`, or the hidden vault beside it.
     *
     * **Decided by purity, here, and not by any caller.** It is the same
     * placement as the NSFW gate a few lines above and it lives in the same
     * function's reach for the same reason CLAUDE.md gives about indexing: a
     * rule about explicit content that a feature has to remember is a rule that
     * one feature will forget. Every route into this tier — a fresh download
     * after the destination was re-pointed at the card, the offload screen
     * emptying the private library, a single move out of it — lands explicit
     * images in the vault without knowing the vault exists.
     *
     * `sketchy` is **not** vaulted, matching `StorageSettings.bucketFor`: it
     * follows the safe destination everywhere else in the app, and a folder that
     * disagreed with the setting the user configured would be its own surprise.
     */
    private fun rootFor(
        request: ImageWrite,
        tree: Uri,
        target: OutsideGalleryTarget,
    ): Uri? {
        if (request.purity != "nsfw") return SafDocuments.telaFolderIn(context, tree)
        return SafDocuments.vaultFolderIn(context, tree, target)
    }

    private fun storeOutsideGallery(
        request: ImageWrite,
        target: OutsideGalleryTarget,
    ): Map<String, Any> {
        val tree = target.tree?.let(Uri::parse) ?: return imageStoreFailure("notConfigured")
        // Before anything is created: this tier writes a `.nomedia`, and a tree
        // that resolves onto the gallery's folder would hide it whole. A tree
        // tela cannot even read is refused as well — "is this somebody else's
        // directory" is not answerable there, and unanswerable is not no.
        if (TreeLocation.of(tree)?.overlapsGallery != false) {
            return imageStoreFailure("folderUnavailable")
        }
        val telaFolder = rootFor(request, tree, target)
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
        if (existing != null) {
            writeOverExisting(existing, request, telaFolder, directory)?.let { return it }
        }
        val file = DocumentsContract.createDocument(
            resolver,
            directory,
            request.mimeType,
            request.fileName,
        ) ?: return imageStoreFailure("unavailable")
        return try {
            resolver.openOutputStream(file)?.use { output -> request.writeBytes(output) }
                ?: throw IllegalStateException("document output stream was null")
            verifyLocalCopy(request, file)
            SafDocuments.dropFromOtherFolders(context, telaFolder, directory, request.fileName)
            stored(file, request.tag)
        } catch (error: Exception) {
            SafDocuments.deleteQuietly(context, file)
            throw error
        }
    }

    /**
     * Settles a document already holding [request]'s name, or answers null when
     * it has been cleared away and the caller should create a fresh one.
     *
     * See [ExistingCopyPolicy] for which of the three happens and why.
     */
    private fun writeOverExisting(
        existing: Uri,
        request: ImageWrite,
        telaFolder: Uri,
        directory: Uri,
    ): Map<String, Any>? {
        val matches = matchesLocalCopy(request, existing)
        val result = when (ExistingCopyPolicy.decide(request.localCopyFrom != null, matches)) {
            ExistingCopyPolicy.REUSE -> stored(existing, request.tag)
            ExistingCopyPolicy.REWRITE -> rewriteDocument(existing, request)
            ExistingCopyPolicy.REPLACE -> return replaceable(existing)
        }
        if (result["success"] == true) {
            SafDocuments.dropFromOtherFolders(context, telaFolder, directory, request.fileName)
        }
        return result
    }

    /**
     * Deletes a mismatched offload leftover so a fresh document can take its
     * name. Answers null once it is gone, a failure when it would not go — a
     * `createDocument` beside it would only produce `wallhaven-abc123 (1).jpg`.
     */
    private fun replaceable(existing: Uri): Map<String, Any>? =
        if (SafDocuments.deleteQuietly(context, existing)) null else imageStoreFailure("unavailable")

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
        verifyLocalCopy(request, file)
        return stored(file, request.tag)
    }

    private fun verifyLocalCopy(request: ImageWrite, written: Uri) =
        localCopies.verify(request.expectedDigest?.invoke(), request.localCopyFrom, written)

    private fun matchesLocalCopy(request: ImageWrite, existing: Uri): Boolean =
        localCopies.matches(request.localCopyFrom, existing)

    private fun storePrivately(request: ImageWrite): Map<String, Any> {
        val directory = TagFolders.privateDirectory(context, request.tag)
            ?: return imageStoreFailure("unavailable")
        if (!TelaDirectories.ensure(directory)) return imageStoreFailure("unavailable")
        val file = File(directory, request.fileName)
        file.outputStream().use { output -> request.writeBytes(output) }
        dropOtherPrivateTags(request, file)
        return stored(Uri.fromFile(file), request.tag)
    }

    /**
     * Removes this wallpaper's copies under *other* tags, once the new one has
     * landed.
     *
     * **One wallpaper, one tag.** Downloading something you already have, under
     * a different tag, means "file it there" — not "keep two". That is the same
     * judgement the gallery and SAF writers already make about re-downloading at
     * all: both look the file up and rewrite it in place, because `insert` and
     * `createDocument` de-duplicate rather than overwrite and left the user with
     * `wallhaven-abc123 (1).jpg` (owner, 2026-07-19). A tag folder is a new way
     * to end up with the same pile.
     *
     * **After the write, never before.** Moving the old copy first would leave a
     * failed download having relocated a file the user already had, and a
     * truncated one where it used to be. Written-then-swept costs a moment of
     * two copies existing and cannot lose anything.
     */
    private fun dropOtherPrivateTags(request: ImageWrite, written: File) {
        TelaDirectories.privateFiles(context)
            .filter { it.name == request.fileName && it.absolutePath != written.absolutePath }
            .forEach { it.delete() }
    }

    /**
     * Streams a file already on this device into [output].
     *
     * Goes through the ContentResolver, which is what makes one function cover
     * all three tiers: a MediaStore image, a SAF document and a `file:` URI all
     * open the same way.
     */
    private fun copyLocal(from: Uri, output: OutputStream): StreamDigest {
        context.contentResolver.openInputStream(from)?.use { input ->
            return copyAndDigest(input, output)
        }
        throw IllegalStateException("no input stream for the stored image")
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
     * The answer a successful write gives, naming the tag it **actually** used.
     *
     * Reported rather than assumed by the caller, for the reason the tier
     * already is: the adapter has the last word. A sweep that could not remove
     * an older copy, or a tier that ignored the tag, must not be described to
     * the user — or written into a history row — as the tag they asked for.
     */
    private fun stored(location: Uri, tag: String? = null): Map<String, Any> {
        val answer = mutableMapOf<String, Any>(
            "success" to true,
            "location" to location.toString(),
        )
        // Absent rather than null for an untagged write, so the response reads
        // back the same as it did before tags existed.
        if (tag != null) answer["tag"] = tag
        return answer
    }

    private companion object {
        const val NETWORK_TIMEOUT_MS = 30_000
        val SUPPORTED_PURITIES = setOf("sfw", "sketchy", "nsfw")
        val SUPPORTED_TIERS = setOf("sharedGallery", "filesOutsideGallery", "appPrivate")
    }
}
