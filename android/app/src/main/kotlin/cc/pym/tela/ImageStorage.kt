package cc.pym.tela

import android.content.Context
import android.net.Uri

/**
 * One image to fetch from the network and file into a tier.
 *
 * [tag] is the folder inside that tier, or null for the tier's own root — the
 * shape every download had before tags existed, and still the ordinary one. It
 * is validated by [TagFolders.isValid] before any path is built from it; see
 * [TierWriting.write].
 */
data class ImageStoreRequest(
    val source: String,
    val id: String,
    val imageUrl: String,
    val purity: String,
    val tier: String,
    val tag: String? = null,
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
    val tag: String? = null,
)

/**
 * Android-only persistence boundary for tela's three image storage tiers.
 *
 * The one door every caller comes through — `ImageStoreChannel`,
 * `DownloadDeleting` and the Kotlin suite all hold an `ImageStorage(context)`
 * — behind which the work is five collaborators with one story each:
 * [TierWriting] puts an image into a tier, [TierDeleting] takes it out,
 * [PrivateTierListing] reads back the one tier nothing else can show,
 * [StoredImageReading] gets at the bytes of a file tela did not just write, and
 * [StoredImageMeasuring] says how big it is and which disk it is on.
 *
 * They are reached through this facade rather than directly so that the purity
 * gate, the traversal guards and the "already gone counts as deleted" rule each
 * keep exactly one home — the reason this class was 807 lines before the split
 * and why the pieces are not merely files.
 *
 * ```
 * ImageStorage(context).store(request, OutsideGalleryTarget(tree, "tela"))
 * ```
 */
class ImageStorage(private val context: Context) {
    /** Downloads [request]'s image into its tier. See [TierWriting.store]. */
    fun store(request: ImageStoreRequest, target: OutsideGalleryTarget): Map<String, Any> =
        TierWriting(context).store(request, target)

    /** Copies an image already on this device into [request]'s tier. */
    fun copy(request: ImageCopyRequest, target: OutsideGalleryTarget): Map<String, Any> =
        TierWriting(context).copy(request, target)

    /** Moves a stored image into another tag folder within its own tier. */
    fun retag(
        tier: String,
        location: Uri,
        tag: String?,
        outsideGalleryTree: String?,
    ): Map<String, Any> =
        StoredImageRetagging(context).retag(tier, location, tag, outsideGalleryTree)

    /** Lists the private library — app-private tier and vault — newest first. */
    fun listPrivate(target: OutsideGalleryTarget): Map<String, Any> =
        PrivateTierListing(context).listPrivate(target)

    /** Lists the app-private tier alone. See [PrivateTierListing.listAppPrivate]. */
    fun listAppPrivate(): Map<String, Any> = PrivateTierListing(context).listAppPrivate()

    /** Deletes one app-private image, named by its `source-id` [key]. */
    fun deletePrivate(key: String): Map<String, Any> = TierDeleting(context).deletePrivate(key)

    /** Hard-deletes a downloaded file from its [tier] — the file, not an index. */
    fun deleteDownload(tier: String, location: Uri): Map<String, Any> =
        TierDeleting(context).deleteDownload(tier, location)

    /** Whether MediaStore still has a row at [location], stale file or not. */
    fun galleryRowExists(location: Uri): Boolean = TierDeleting(context).galleryRowExists(location)

    /** Whether the file at [location] can still be opened. */
    fun canRead(location: Uri): Map<String, Any> = StoredImageReading(context).canRead(location)

    /** Bytes on disk at [location], and whether that disk is a removable card. */
    fun measure(location: Uri): Map<String, Any> = StoredImageMeasuring(context).measure(location)

    /** Copies a MediaStore or SAF image into a decodable cache file. */
    fun materialise(location: Uri): Map<String, Any> =
        StoredImageReading(context).materialise(location)

    /** Downloads a not-yet-downloaded wallpaper into the same cache folder. */
    fun materialiseRemote(imageUrl: String): Map<String, Any> =
        StoredImageReading(context).materialiseRemote(imageUrl)

    /** Decodes a downsampled grid thumbnail, with the source's pixel bounds. */
    fun materialiseThumbnail(location: Uri, maxDimensionPx: Int): Map<String, Any> =
        StoredImageReading(context).materialiseThumbnail(location, maxDimensionPx)

    /** Deletes a throwaway preview, refusing any path outside the cache folder. */
    fun releasePreview(path: String): Map<String, Any> =
        StoredImageReading(context).releasePreview(path)
}
