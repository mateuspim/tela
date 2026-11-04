package cc.pym.tela

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract

/**
 * The `filesOutsideGallery` writer: a granted SAF tree, a `.nomedia` marker and
 * the hidden vault for explicit images.
 *
 * Out of [TierWriting] because this is the one tier whose cost is binder round
 * trips against a provider tela does not own, and it is the one that has to be
 * timed phase by phase ([PhaseClock]) when a card copy is slow.
 *
 * ```
 * DocumentTierWriting(context).store(write, OutsideGalleryTarget(tree, "tela"))
 * ```
 */
internal class DocumentTierWriting(private val context: Context) {
    private val localCopies = LocalCopyChecks(context)

    /** Writes [request] into the granted tree, answering like [TierWriting.store]. */
    fun store(request: ImageWrite, target: OutsideGalleryTarget): Map<String, Any> {
        val clock = PhaseClock("sdcopy")
        try {
            return storeTimed(request, target, clock)
        } finally {
            clock.finish()
        }
    }

    private fun storeTimed(
        request: ImageWrite,
        target: OutsideGalleryTarget,
        clock: PhaseClock,
    ): Map<String, Any> {
        val tree = target.treeFor(request.purity)?.let(Uri::parse)
            ?: return imageStoreFailure("notConfigured")
        // Before anything is created: this tier writes a `.nomedia`, and a tree
        // that resolves onto the gallery's folder would hide it whole. A tree
        // tela cannot even read is refused as well — "is this somebody else's
        // directory" is not answerable there, and unanswerable is not no.
        if (TreeLocation.of(tree)?.overlapsGallery != false) {
            return imageStoreFailure("folderUnavailable")
        }
        val folders = clock.phase("folders") { prepareFolders(request, tree, target) }
            ?: return imageStoreFailure("unavailable")
        return place(request, folders, clock)
    }

    /** The two folders a write touches: the root and the tag folder inside it. */
    private class Folders(val root: Uri, val directory: Uri)

    /**
     * Finds or creates the root, the tag folder and their `.nomedia` markers,
     * or null when any of them cannot be.
     *
     * The tag's own folder is marked too. A `.nomedia` in the parent already
     * covers the subtree for Android's scanner, so this is belt and braces —
     * but this tier's entire contract is "not in the gallery index", the
     * marker costs one document, and a subtree exclusion is a scanner
     * behaviour rather than a documented guarantee. See `TreeLocation`, which
     * records what a mis-marked directory cost the owner once already.
     */
    private fun prepareFolders(
        request: ImageWrite,
        tree: Uri,
        target: OutsideGalleryTarget,
    ): Folders? {
        val root = rootFor(request, tree, target) ?: return null
        if (!SafDocuments.ensureNoMediaMarker(context, root)) return null
        val directory = SafDocuments.tagFolderIn(context, root, request.tag) ?: return null
        if (directory != root && !SafDocuments.ensureNoMediaMarker(context, directory)) return null
        return Folders(root, directory)
    }

    private fun place(
        request: ImageWrite,
        folders: Folders,
        clock: PhaseClock,
    ): Map<String, Any> {
        // Same duplicate trap as the gallery tier, through a different door:
        // `createDocument` also renames rather than replacing, so a second
        // download of one wallpaper produced `wallhaven-abc123 (1).jpg`. This is
        // the desktop-sync path, where a directory quietly accumulating near
        // copies of every wallpaper is worse still.
        val existing = clock.phase("lookup") {
            SafDocuments.findChild(context, folders.directory, request.fileName)
        }
        if (existing != null) {
            val settled = writeOverExisting(existing, request, folders, clock)
            if (settled != null) return settled
        }
        return createAndWrite(request, folders, clock)
    }

    private fun createAndWrite(
        request: ImageWrite,
        folders: Folders,
        clock: PhaseClock,
    ): Map<String, Any> {
        val resolver = context.contentResolver
        val file = clock.phase("create") {
            DocumentsContract.createDocument(
                resolver,
                folders.directory,
                request.mimeType,
                request.fileName,
            )
        } ?: return imageStoreFailure("unavailable")
        return try {
            clock.phase("write") {
                resolver.openOutputStream(file)?.use { output -> request.writeBytes(output) }
                    ?: throw IllegalStateException("document output stream was null")
            }
            clock.phase("verify") { verifyLocalCopy(request, file) }
            sweep(request, folders, clock)
            storedAnswer(file, request.tag)
        } catch (error: Exception) {
            SafDocuments.deleteQuietly(context, file)
            throw error
        }
    }

    private fun sweep(request: ImageWrite, folders: Folders, clock: PhaseClock) {
        clock.phase("sweep") {
            SafDocuments.dropFromOtherFolders(
                context,
                folders.root,
                folders.directory,
                request.fileName,
            )
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
        folders: Folders,
        clock: PhaseClock,
    ): Map<String, Any>? {
        val matches = clock.phase("compare") { matchesLocalCopy(request, existing) }
        val result = when (ExistingCopyPolicy.decide(request.localCopyFrom != null, matches)) {
            ExistingCopyPolicy.REUSE -> storedAnswer(existing, request.tag)
            ExistingCopyPolicy.REWRITE -> clock.phase("write") { rewriteDocument(existing, request) }
            ExistingCopyPolicy.REPLACE -> return replaceable(existing)
        }
        if (result["success"] == true) sweep(request, folders, clock)
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
     * same reasons [TierWriting] gives for the gallery rewrite.
     */
    private fun rewriteDocument(file: Uri, request: ImageWrite): Map<String, Any> {
        context.contentResolver.openOutputStream(file, "wt")?.use { output ->
            request.writeBytes(output)
        } ?: throw IllegalStateException("document output stream was null")
        verifyLocalCopy(request, file)
        return storedAnswer(file, request.tag)
    }

    private fun verifyLocalCopy(request: ImageWrite, written: Uri) =
        localCopies.verify(request.expectedDigest?.invoke(), request.localCopyFrom, written)

    private fun matchesLocalCopy(request: ImageWrite, existing: Uri): Boolean =
        localCopies.matches(request.localCopyFrom, existing)

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
}
