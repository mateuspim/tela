package cc.pym.tela

import android.content.Context
import android.net.Uri

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
 * Android-only persistence boundary for tela's three image storage tiers.
 *
 * The one door every caller comes through — `ImageStoreChannel`,
 * `DownloadDeleting` and the Kotlin suite all hold an `ImageStorage(context)`
 * — behind which the work is four collaborators with one story each:
 * [TierWriting] puts an image into a tier, [TierDeleting] takes it out,
 * [PrivateTierListing] reads back the one tier nothing else can show, and
 * [StoredImageReading] gets at the bytes of a file tela did not just write.
 *
 * They are reached through this facade rather than directly so that the purity
 * gate, the traversal guards and the "already gone counts as deleted" rule each
 * keep exactly one home — the reason this class was 807 lines before the split
 * and why the pieces are not merely files.
 *
 * ```
 * ImageStorage(context).store(request, outsideGalleryTree)
 * ```
 */
class ImageStorage(private val context: Context) {
    /** Downloads [request]'s image into its tier. See [TierWriting.store]. */
    fun store(request: ImageStoreRequest, outsideGalleryTree: String?): Map<String, Any> =
        TierWriting(context).store(request, outsideGalleryTree)

    /** Copies an image already on this device into [request]'s tier. */
    fun copy(request: ImageCopyRequest, outsideGalleryTree: String?): Map<String, Any> =
        TierWriting(context).copy(request, outsideGalleryTree)

    /** Lists the app-private tier, newest first. */
    fun listPrivate(): Map<String, Any> = PrivateTierListing(context).listPrivate()

    /** Deletes one app-private image, named by its `source-id` [key]. */
    fun deletePrivate(key: String): Map<String, Any> = TierDeleting(context).deletePrivate(key)

    /** Hard-deletes a downloaded file from its [tier] — the file, not an index. */
    fun deleteDownload(tier: String, location: Uri): Map<String, Any> =
        TierDeleting(context).deleteDownload(tier, location)

    /** Whether MediaStore still has a row at [location], stale file or not. */
    fun galleryRowExists(location: Uri): Boolean = TierDeleting(context).galleryRowExists(location)

    /** Whether the file at [location] can still be opened. */
    fun canRead(location: Uri): Map<String, Any> = StoredImageReading(context).canRead(location)

    /** Copies a MediaStore or SAF image into a decodable cache file. */
    fun materialise(location: Uri): Map<String, Any> =
        StoredImageReading(context).materialise(location)

    /** Deletes a throwaway preview, refusing any path outside the cache folder. */
    fun releasePreview(path: String): Map<String, Any> =
        StoredImageReading(context).releasePreview(path)
}
