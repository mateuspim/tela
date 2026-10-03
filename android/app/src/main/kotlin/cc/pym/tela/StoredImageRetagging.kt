package cc.pym.tela

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.MediaStore
import java.io.File

/**
 * Moving a stored image from one tag folder to another, **inside its own tier**.
 *
 * The cheap half of retagging, and the reason it exists rather than leaving the
 * job to copy-then-delete: none of these paths move a byte, and none of them
 * raises the system delete confirmation that `MoveStoredImages` has to batch on
 * API 30+. Retagging thirty gallery downloads is a metadata update thirty times,
 * not thirty megabytes and a prompt.
 *
 * **Within a tier only, and that is a safety property, not a limitation.** A tag
 * selects a directory inside a destination the purity gate has already approved;
 * changing tiers is [TierWriting]'s business, where that gate lives. Nothing
 * here can move an explicit image into the gallery, because nothing here can
 * change which tier a file is in.
 *
 * Every failure is an ordinary answer rather than a throw. MediaStore ownership
 * does not survive a reinstall (the 2026-08-11 key change cost exactly that), a
 * document provider may refuse a move, and a caller that hears "no" falls back
 * to copy-then-delete. A crash would leave it nothing to fall back from.
 *
 * ```
 * StoredImageRetagging(context).retag("sharedGallery", location, "anime", null)
 * ```
 */
internal class StoredImageRetagging(private val context: Context) {
    /**
     * Moves the file at [location] into [tag]'s folder within [tier].
     *
     * A null [tag] moves it back to the tier root — "no tag" is a destination
     * like any other, not a refusal to act.
     *
     * Answers `{success, location}` with the file's **new** location, which the
     * caller must store: the SAF and private tiers both change their URI, and a
     * history row still pointing at the old one describes a file that is not
     * there.
     */
    fun retag(
        tier: String,
        location: Uri,
        tag: String?,
        outsideGalleryTree: String?,
    ): Map<String, Any> {
        if (tag != null && !TagFolders.isValid(tag)) return imageStoreFailure("unavailable")
        return try {
            when (tier) {
                "sharedGallery" -> retagGalleryImage(location, tag)
                "filesOutsideGallery" -> retagDocument(location, tag, outsideGalleryTree)
                "appPrivate" -> retagPrivateFile(location, tag)
                else -> imageStoreFailure("unavailable")
            }
        } catch (_: Exception) {
            imageStoreFailure("unavailable")
        }
    }

    /**
     * Updates the MediaStore row's `RELATIVE_PATH`, which *is* the move.
     *
     * The URI is stable across it — MediaStore keeps the row id — so the caller
     * gets the location it already had, and a history row that was never updated
     * would still be correct. That is luck rather than design, and the answer
     * still carries the location so no caller learns to depend on it.
     *
     * A file this app does not own throws `SecurityException` here instead of
     * moving. That is not hypothetical: media ownership is per install, and
     * every file written before the 2026-08-11 reinstall belongs to nobody as
     * far as this package is concerned. Those fall back to copy-then-delete.
     */
    private fun retagGalleryImage(location: Uri, tag: String?): Map<String, Any> {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.RELATIVE_PATH, TagFolders.galleryPath(tag))
        }
        val updated = context.contentResolver.update(location, values, null, null)
        if (updated <= 0) return imageStoreFailure("unavailable")
        return moved(location)
    }

    /**
     * Moves the SAF document into the tag's folder under the granted tree.
     *
     * `moveDocument` needs the document's **current parent**, which a document
     * URI does not carry, so the parent is found by asking each candidate folder
     * whether it holds this document — the tela folder itself and each of its
     * tag children. A handful of queries for a retag the user asked for; the
     * alternative is storing a parent alongside every location for the one
     * operation that wants it.
     *
     * The destination folder is created and `.nomedia`-marked on the way, the
     * same as a download into it would be: a tag folder that exists only because
     * something was moved into it must not be the one folder in this tier that
     * the gallery indexes.
     */
    private fun retagDocument(
        location: Uri,
        tag: String?,
        outsideGalleryTree: String?,
    ): Map<String, Any> {
        val tree = outsideGalleryTree?.let(Uri::parse) ?: return imageStoreFailure("notConfigured")
        val telaFolder = SafDocuments.telaFolderIn(context, tree)
            ?: return imageStoreFailure("unavailable")
        val target = SafDocuments.tagFolderIn(context, telaFolder, tag)
            ?: return imageStoreFailure("unavailable")
        if (target != telaFolder && !SafDocuments.ensureNoMediaMarker(context, target)) {
            return imageStoreFailure("unavailable")
        }
        val parent = SafDocuments.parentOf(context, telaFolder, location)
            ?: return imageStoreFailure("unavailable")
        if (parent == target) return moved(location)
        val destination = DocumentsContract.moveDocument(
            context.contentResolver,
            location,
            parent,
            target,
        ) ?: return imageStoreFailure("unavailable")
        // Moving a tag's last wallpaper out empties it as surely as deleting it.
        EmptyTagFolders.pruneAfterDocument(context, location)
        return moved(destination)
    }

    /**
     * Renames the private file into the tag's directory.
     *
     * Both ends are confined to the tier before anything moves — the source
     * because it arrived over a method channel ([TelaDirectories.holdsPrivateFile]),
     * the destination because [TagFolders.privateDirectory] refuses a tag that
     * is not a legal folder name.
     *
     * A rename that fails is answered, not retried as copy-and-delete: within
     * one directory tree it only fails for reasons a copy would hit too, and the
     * caller above has a real fallback that can also handle the other tiers.
     */
    private fun retagPrivateFile(location: Uri, tag: String?): Map<String, Any> {
        val path = location.path ?: return imageStoreFailure("unavailable")
        val file = File(path)
        if (!TelaDirectories.holdsPrivateFile(context, file)) {
            return imageStoreFailure("unavailable")
        }
        if (ImageFileNaming.keyOf(file.name) == null) return imageStoreFailure("unavailable")
        val directory = TagFolders.privateDirectory(context, tag)
            ?: return imageStoreFailure("unavailable")
        if (!TelaDirectories.ensure(directory)) return imageStoreFailure("unavailable")
        val destination = File(directory, file.name)
        if (destination.absolutePath == file.absolutePath) return moved(location)
        if (!file.renameTo(destination)) return imageStoreFailure("unavailable")
        EmptyTagFolders.pruneAfterPrivate(context, file)
        return moved(Uri.fromFile(destination))
    }

    private fun moved(location: Uri): Map<String, Any> = mapOf(
        "success" to true,
        "location" to location.toString(),
    )
}
