package cc.pym.tela

import android.net.Uri
import android.os.Build
import io.flutter.plugin.common.MethodCall

/**
 * What a delete batch resolved to before any prompt: the gallery rows the OS
 * must confirm, and the locations that are already gone.
 */
internal data class DeletionPlan(val confirm: List<Uri>, val deleted: List<String>)

/**
 * Deletes what tela can delete itself, and sorts the rest into live gallery rows
 * and stale ones.
 *
 * Separated from [ImageStoreChannel] because this is the *decision* — which rows
 * go silently, which need the OS's own prompt, which are already gone — with no
 * threads, no channel and no activity in it. That makes it the piece worth
 * reading on its own, and the piece a test can drive directly.
 *
 * **A gallery row whose MediaStore row no longer exists counts as deleted**,
 * because it is: the end state the user asked for is already true. Handing it to
 * `MediaStore.createDeleteRequest` instead throws `IllegalArgumentException` on
 * the main thread and kills the process — and since the history is where those
 * rows live and *clearing the history is the only gesture that removes them*,
 * every retry died before trimming anything and the user could not escape without
 * wiping app data (owner, 2026-07-28).
 *
 * It needs no mistake of ours to happen: a `sharedGallery` row outlives its file
 * whenever the file goes away behind tela's back — deleted from Photos, from a
 * file manager, by a storage cleaner, or on a card that was unmounted. Rendering
 * already tolerates that; it is what the missing badge shows.
 */
internal fun planDeletions(
    storage: ImageStorage,
    items: List<Pair<String, Uri>>,
): DeletionPlan {
    val gallery = mutableListOf<Uri>()
    val deleted = mutableListOf<String>()
    for ((tier, uri) in items) {
        if (tier == "sharedGallery" && systemConfirmsGalleryDelete()) {
            gallery.add(uri)
        } else if (storage.deleteDownload(tier, uri)["success"] == true) {
            deleted.add(uri.toString())
        }
    }
    val (live, stale) = gallery.partition { storage.galleryRowExists(it) }
    return DeletionPlan(live, deleted + stale.map(Uri::toString))
}

/** The (tier, location) pairs a delete batch names, or null for a malformed call. */
internal fun readDeletionItems(call: MethodCall): List<Pair<String, Uri>>? {
    val raw = call.argument<List<Map<String, String>>>("items") ?: return null
    return raw.mapNotNull { item ->
        val tier = item["tier"]
        val location = item["location"]
        if (tier == null || location == null) null else tier to Uri.parse(location)
    }
}

/** True on API 30+, where every gallery delete goes through the OS prompt. */
internal fun systemConfirmsGalleryDelete(): Boolean =
    Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

/**
 * A delete batch's answer: what went, whether or not everything did.
 *
 * Always a success, because "some of these were already gone" and "the user
 * declined the prompt" are outcomes, not failures — Dart forgets exactly the rows
 * named here and leaves the others alone.
 */
internal fun deletionOutcome(deleted: List<String>): Map<String, Any> =
    mapOf("success" to true, "deleted" to deleted)
