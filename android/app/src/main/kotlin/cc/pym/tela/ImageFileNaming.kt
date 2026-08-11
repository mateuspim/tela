package cc.pym.tela

import android.content.Context
import android.net.Uri

/**
 * What a stored image is called on disk, and what type it is.
 *
 * One home for the name because the name is an identity here, not a label: the
 * app-private tier writes no database row, so `source-id.ext` is the **only**
 * record of where such an image came from, and [PrivateTierListing] drops any
 * file that does not match [PRIVATE_FILE]. A second spelling of any of this
 * would make a stored image silently unlistable.
 *
 * ```
 * val name = ImageFileNaming.fileName("wallhaven", "abc123", "jpg")
 * // -> "wallhaven-abc123.jpg"
 * ```
 */
internal object ImageFileNaming {
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
    fun fileName(source: String, id: String, extension: String): String {
        require(VALID_SOURCE.matches(source)) { "source id has an invalid shape" }
        require(VALID_ID.matches(id)) { "wallpaper id has an invalid shape" }
        return "$source-$id.$extension"
    }

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
    fun keyOf(fileName: String): String? {
        val match = PRIVATE_FILE.matchEntire(fileName) ?: return null
        return "${match.groupValues[1]}-${match.groupValues[2]}"
    }

    /** Whether [key] is a `source-id` pair tela could have written. */
    fun isValidKey(key: String): Boolean = VALID_KEY.matches(key)

    /** The extension a remote image's URL implies, defaulting to `jpg`. */
    fun urlExtension(imageUrl: String): String {
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
    fun extensionOf(context: Context, from: Uri): String {
        val mime = context.contentResolver.getType(from)
        return when {
            mime != null -> mimeExtension(mime)
            else -> urlExtension(from.lastPathSegment.orEmpty())
        }
    }

    /** The MIME type a stored file's [extension] declares to MediaStore and SAF. */
    fun mimeType(extension: String): String {
        return when (extension) {
            "png" -> "image/png"
            "webp" -> "image/webp"
            else -> "image/jpeg"
        }
    }

    private fun mimeExtension(mime: String): String {
        return when (mime.substringBefore(';').trim().lowercase()) {
            "image/png" -> "png"
            "image/webp" -> "webp"
            else -> "jpg"
        }
    }

    /**
     * A wallpaper id, as its own source issued it.
     *
     * `-` is deliberately **not** here, though it was until 2026-07-26: a
     * file is now named `source-id`, and a hyphen on either side of that
     * join would make the split ambiguous. No source issues one — Wallhaven's
     * ids are lowercase alphanumeric and a booru's are digits — so this
     * narrows an allowlist without narrowing what tela can store.
     */
    private val VALID_ID = Regex("[A-Za-z0-9_]{1,64}")

    /** Mirrors Dart's `SourceId` shape, which is what composes these names. */
    private val VALID_SOURCE = Regex("[a-z0-9_]{1,32}")

    /** The `source-id` pair as one string, the form [TierDeleting.deletePrivate] takes. */
    private val VALID_KEY = Regex("[a-z0-9_]{1,32}-[A-Za-z0-9_]{1,64}")

    /**
     * Matches only the names tela writes, capturing the source and the id.
     *
     * Old `wallhaven-*` files need no migration: they are all Wallhaven's,
     * and group 1 reads back exactly that.
     */
    private val PRIVATE_FILE =
        Regex("([a-z0-9_]{1,32})-([A-Za-z0-9_]{1,64})\\.(jpg|jpeg|png|webp)")
}
