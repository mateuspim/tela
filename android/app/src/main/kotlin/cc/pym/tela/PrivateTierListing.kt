package cc.pym.tela

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.File

/**
 * Reading back the private library, newest first — **both of its homes**.
 *
 * The app-private tier is one of them, and it is the reason this class exists:
 * those files are visible to nothing but tela, so without a listing they could
 * only be written, never seen. Since 2026-08-25 there is a second, and it needs
 * the listing for the same reason and more urgently: the hidden vault on the
 * files tier is a dot-prefixed folder no file manager shows by default, and
 * MediaStore never indexes that tier at all. See [SafVaultListing].
 *
 * The gallery tier is still not listable and never will be — that one lands
 * where Photos already shows it.
 *
 * ```
 * PrivateTierListing(context).listPrivate(target)["images"]
 * ```
 */
internal class PrivateTierListing(private val context: Context) {
    /**
     * Every private image, newest first, with the bounds the grid shapes tiles
     * to.
     *
     * Tagged images live one directory down, and the walk that finds them is
     * [TelaDirectories.privateFiles] rather than a listing of its own — it is
     * shared with the delete, which must never search shallower than this reads.
     *
     * **Sorted after the merge, not before.** Each half arrives newest-first on
     * its own, and concatenating two sorted lists does not give a sorted one:
     * the vault's newest would sit below the app-private tier's oldest, which
     * on a device that has just offloaded is every image the user has.
     */
    fun listPrivate(target: OutsideGalleryTarget): Map<String, Any> {
        val vault = SafVaultListing(context).list(target)
        return answer(appPrivateRows() + vault)
    }

    /**
     * The app-private half alone — the vault is never opened.
     *
     * For the caller that wants what is still **on built-in storage**: the
     * offload survey, which adds up what moving to a card would free and so has
     * nothing to ask of files already on one. It used to call [listPrivate] and
     * throw the vault half away, which cost a SAF walk and a header read per
     * card file — on a device that had already offloaded once, over a thousand
     * of them — to reach an answer none of them were part of. The screen got
     * slower every time it was used successfully (owner, 2026-08-25).
     *
     * Rows are shaped exactly as [listPrivate]'s, bounds included: the two
     * differ in which homes they read, never in what a row means.
     */
    fun listAppPrivate(): Map<String, Any> = answer(appPrivateRows())

    private fun appPrivateRows(): List<Map<String, Any>> =
        TelaDirectories.privateFiles(context).mapNotNull { file -> describe(file) }

    /** Rows newest-first under the `success`/`images` shape both listings answer. */
    private fun answer(rows: List<Map<String, Any>>): Map<String, Any> =
        mapOf("success" to true, "images" to rows.sortedByDescending { it["savedAt"] as Long })

    /**
     * One image's row, or null for a file tela did not write.
     *
     * The name is the identity: a file whose name does not parse has no source
     * and no id to report, and reporting it under a guess is worse than
     * omitting it.
     */
    private fun describe(file: File): Map<String, Any>? {
        val key = ImageFileNaming.keyOf(file.name) ?: return null
        val (width, height) = pixelBounds(file)
        val row = mutableMapOf<String, Any>(
            "ref" to key,
            "location" to Uri.fromFile(file).toString(),
            "savedAt" to file.lastModified(),
            "sizeBytes" to file.length(),
            "width" to width,
            "height" to height,
            "tier" to "appPrivate",
        )
        // Absent rather than null for an untagged image: the tier root is where
        // every private file lived before tags, and a row that never mentions a
        // tag reads back the same on both sides of that change.
        TagFolders.tagOf(context, file)?.let { tag -> row["tag"] = tag }
        return row
    }

    /**
     * Reads a file's pixel dimensions without decoding its pixels.
     *
     * `inJustDecodeBounds` fills `outWidth`/`outHeight` from the header alone, so
     * the private grid can shape each tile to its file without holding a whole
     * 6K bitmap in memory. A corrupt or truncated file leaves both at -1, which
     * Dart reads back as unknown and renders as a safe broken-image state.
     */
    private fun pixelBounds(file: File): Pair<Int, Int> {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        return try {
            BitmapFactory.decodeFile(file.absolutePath, options)
            options.outWidth to options.outHeight
        } catch (_: Exception) {
            -1 to -1
        }
    }
}
