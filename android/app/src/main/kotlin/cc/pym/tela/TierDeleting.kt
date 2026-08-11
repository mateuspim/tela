package cc.pym.tela

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.MediaStore
import java.io.FileNotFoundException

/**
 * Hard-deleting a stored image from the tier it landed in.
 *
 * The file, not an index entry — the counterpart to [TierWriting], and distinct
 * from `DownloadDeleting`, which owns the *batch* the user confirms on screen.
 * The rule every path here shares: **a file that is already gone counts as
 * deleted**, because the end state the user asked for has been reached.
 *
 * ```
 * TierDeleting(context).deleteDownload("appPrivate", location)
 * ```
 */
internal class TierDeleting(private val context: Context) {
    /**
     * Deletes one app-private image, named by its `source-id` [key].
     *
     * The key is matched against the naming allowlist before it is used to
     * build any path. It arrives over a method channel, and a key like
     * `../../databases/tela` is how a listing feature becomes an
     * arbitrary-file-delete.
     *
     * Source-qualified so that two sources issuing the same number cannot
     * delete each other's file — the reason `WallpaperRef` exists on the Dart
     * side, applied to the one tier whose identity lives in a file name.
     *
     * **A file that is already gone counts as deleted**, and answering
     * `unavailable` for one is the bug this used to have. See
     * [deleteDocumentAt] for the whole argument; it is the same rule, and the
     * empty match list here is exactly the "already gone" case.
     */
    fun deletePrivate(key: String): Map<String, Any> {
        if (!ImageFileNaming.isValidKey(key)) return imageStoreFailure("unavailable")
        val matches = TelaDirectories.privateImages(context)
            .listFiles()
            ?.filter { it.isFile && ImageFileNaming.keyOf(it.name) == key }
            ?: emptyList()
        if (matches.isEmpty()) return mapOf("success" to true)
        if (!matches.all { it.delete() }) return imageStoreFailure("unavailable")
        return mapOf("success" to true)
    }

    /**
     * Hard-deletes a downloaded file from its [tier] — the file, not an index.
     *
     * The gallery tier on API 30+ is deliberately **not** here: it needs an
     * Activity to launch `MediaStore.createDeleteRequest`, which `DownloadDeleting`
     * owns. This handles the app-private file, the SAF document, and the direct
     * gallery delete the older API (29) still permits. appPrivate reuses the
     * guarded [deletePrivate] by recovering the id from the file's own name.
     */
    fun deleteDownload(tier: String, location: Uri): Map<String, Any> {
        return when (tier) {
            "appPrivate" -> deletePrivateAt(location)
            "filesOutsideGallery" -> deleteDocumentAt(location)
            "sharedGallery" -> deleteGalleryDirectly(location)
            else -> imageStoreFailure("unavailable")
        }
    }

    /**
     * Whether MediaStore still has a row at [location].
     *
     * Asked before a gallery delete, and deliberately **not** `canRead`: a row
     * can outlive its file, and such a row is still perfectly deletable. Only the
     * row's existence decides whether `MediaStore.createDeleteRequest` will
     * accept it — see [planDeletions] for why a stale one may never reach it.
     */
    fun galleryRowExists(location: Uri): Boolean {
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        return rowExists(location, projection)
    }

    /** Recovers the key from the private file's name so [deletePrivate]'s listing
     *  guard still stands — a location is a `file:` URI tela itself wrote. */
    private fun deletePrivateAt(location: Uri): Map<String, Any> {
        val key = location.lastPathSegment?.let(ImageFileNaming::keyOf)
            ?: return imageStoreFailure("unavailable")
        val result = deletePrivate(key)
        return if (result["success"] == true) deletionOutcome(listOf(location.toString())) else result
    }

    /**
     * Deletes the SAF document tela created under the user's granted tree.
     *
     * **A document that is already gone counts as deleted**, because it is: the
     * end state the user asked for has been reached by other means. This is the
     * same decision [planDeletions] records for the gallery tier — it was made
     * on 2026-07-28 and applied only there, because there a stale row *crashed*
     * and here it merely failed in silence.
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
     * tier's up-front [galleryRowExists]. There the check exists because
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
            return deletionOutcome(listOf(location.toString()))
        } catch (_: Exception) {
            false
        }
        if (removed || !documentExists(location)) {
            return deletionOutcome(listOf(location.toString()))
        }
        return imageStoreFailure("unavailable")
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
        return rowExists(location, projection)
    }

    /**
     * Whether a provider answers [location] with a row at all.
     *
     * Shared by the two existence questions above because they differ only in
     * which column they ask for, and every failure is false rather than a throw
     * — an unreachable provider is an ordinary state of the world here.
     */
    private fun rowExists(location: Uri, projection: Array<String>): Boolean {
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
     * routes here; `DownloadDeleting` launches the system delete request instead.
     */
    private fun deleteGalleryDirectly(location: Uri): Map<String, Any> {
        val removed = context.contentResolver.delete(location, null, null)
        return if (removed > 0) {
            deletionOutcome(listOf(location.toString()))
        } else {
            imageStoreFailure("unavailable")
        }
    }
}
