package cc.pym.tela

import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import androidx.core.net.toUri

/**
 * The wallpapers auto-rotate may choose from, per tier.
 *
 * **Already-downloaded files only, never a live listing.** A schedule that
 * searched would spend the source's rate ceiling in the background, need a
 * network at whatever hour it fires, and could put a wallpaper nobody has ever
 * seen on the screen. Everything here is a file the user chose to keep.
 *
 * Answers URIs rather than `File`s because two of the three tiers are not
 * files as far as this process is concerned: the gallery tier is MediaStore
 * rows and the outside-gallery tier is a SAF tree. [WallpaperSetting.applyUri]
 * reads all three the same way.
 *
 * Sorted by name, and that matters: the rotation cursor is an *index*, so an
 * unstable order would make "next" mean a different picture every run.
 */
internal object RotationCandidates {
    /**
     * Every candidate in [tier], in a stable order.
     *
     * An empty list is an ordinary answer — a tier nothing has been downloaded
     * to yet — and the worker treats it as nothing to do rather than a failure.
     */
    fun of(context: Context, tier: String, vault: OutsideGalleryTarget): List<Uri> =
        when (tier) {
            "appPrivate" -> appPrivate(context)
            "sharedGallery" -> gallery(context)
            "filesOutsideGallery" -> outsideGallery(context, vault)
            else -> throw IllegalArgumentException(
                "tier must be appPrivate|sharedGallery|filesOutsideGallery, got \"$tier\"",
            )
        }

    /**
     * The app-private tier, root and one level down.
     *
     * Reuses [TelaDirectories.privateFiles] rather than walking again — that
     * function is the one place the tier's depth is decided, and a second walk
     * here would be free to disagree with it.
     */
    private fun appPrivate(context: Context): List<Uri> =
        TelaDirectories.privateFiles(context)
            .sortedBy { it.name }
            .map { it.toUri() }

    /**
     * The MediaStore rows tela wrote under `Pictures/tela`.
     *
     * Queried rather than read off disk: the shared tier is indexed storage,
     * and the row is what the platform will actually let this process open.
     */
    private fun gallery(context: Context): List<Uri> {
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(MediaStore.Images.Media._ID)
        val cursor = context.contentResolver.query(
            collection,
            projection,
            "${MediaStore.Images.Media.RELATIVE_PATH} LIKE ?",
            arrayOf("Pictures/$GALLERY_FOLDER%"),
            "${MediaStore.Images.Media.DISPLAY_NAME} ASC",
        ) ?: return emptyList()
        return cursor.use { rows ->
            val id = rows.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            buildList {
                while (rows.moveToNext()) {
                    add(android.content.ContentUris.withAppendedId(collection, rows.getLong(id)))
                }
            }
        }
    }

    /**
     * The SAF vault, when one is still granted.
     *
     * Reuses [SafVaultListing] rather than walking the tree again: that class
     * already knows the vault's two levels, its tag folders and its legality
     * rules, and a second walk here would be free to disagree with what the
     * private library shows.
     *
     * The tree grant is persisted, so it normally survives to whatever hour the
     * schedule fires — but a user can revoke it and a card can be pulled. Both
     * read as an empty list, which the worker treats as nothing to do rather
     * than a broken schedule.
     */
    private fun outsideGallery(context: Context, vault: OutsideGalleryTarget): List<Uri> =
        SafVaultListing(context).list(vault)
            .mapNotNull { row -> row["location"] as? String }
            .sorted()
            .map(Uri::parse)

    /** The folder name tela writes under `Pictures/`. */
    private const val GALLERY_FOLDER = "tela"
}
