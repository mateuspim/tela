package cc.pym.tela

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri

/**
 * Reading back the hidden vault, so images moved to a card do not vanish.
 *
 * The SAF twin of [PrivateTierListing], and it exists for exactly the reason
 * that one does: these files are visible to nothing the user would think to
 * look in. A dot-prefixed folder is hidden from every file manager by default
 * and MediaStore never indexes this tier, so without this the vault would be a
 * place photos go to disappear — which is what "hidden" must never be allowed
 * to mean inside a photo app.
 *
 * **Only reads a vault that already exists.** A tree with no vault in it is an
 * ordinary empty answer, not a reason to create one: listing is not a write,
 * and a settings screen that conjured a directory just by being opened would
 * leave `.tela` folders in trees nobody stored anything in.
 *
 * ```
 * SafVaultListing(context).list(OutsideGalleryTarget(tree, "tela"))
 * ```
 */
internal class SafVaultListing(private val context: Context) {
    /**
     * Every image in the vault and its tag folders, newest first.
     *
     * Empty for a tree that is not set, a vault that was never created, or a
     * card that is out — none of which is an error the private library should
     * show. It renders what it has, which is the app-private tier.
     */
    fun list(target: OutsideGalleryTarget): List<Map<String, Any>> {
        val vault = vaultIn(target) ?: return emptyList()
        return describeAll(untagged(vault) + tagged(vault))
            .sortedByDescending { row -> row["savedAt"] as Long }
    }

    /** The vault directory, or null when there is nothing to read. */
    private fun vaultIn(target: OutsideGalleryTarget): Uri? {
        val tree = target.tree?.let(Uri::parse) ?: return null
        val name = target.vaultDirectory ?: return null
        return try {
            SafDocuments.existingFolderIn(context, tree, name)
        } catch (_: Exception) {
            // An ejected card or a revoked grant. The private library still has
            // its own tier to show, and a throw here would take that with it.
            null
        }
    }

    private fun untagged(vault: Uri): List<Pair<SafFile, String?>> =
        SafDocuments.filesIn(context, vault).map { file -> file to null }

    /**
     * The tag folders inside the vault, each read as its own shelf.
     *
     * One level deep, matching [TelaDirectories.privateFiles]: a tag is a
     * directory and tags do not nest, so anything deeper is not tela's and is
     * left alone rather than flattened into the listing.
     */
    private fun tagged(vault: Uri): List<Pair<SafFile, String?>> {
        return SafDocuments.subdirectoriesOf(context, vault)
            .filter { (name, _) -> TagFolders.isValid(name) }
            .flatMap { (name, folder) ->
                SafDocuments.filesIn(context, folder).map { file -> file to name }
            }
    }

    /**
     * Describes every file, reading their headers **several at a time**.
     *
     * Each row costs a SAF stream open and a header decode, and both are spent
     * waiting on a binder round trip rather than on the card — 1150 header
     * reads straight off the disk take 1.5s, where the same files through the
     * provider ran at about eleven a second. Serially that is minutes for a
     * vault of a few thousand, paid on every refresh, and the offload's whole
     * job is to make the vault bigger: the listing got slower exactly as the
     * feature succeeded (owner, 2026-08-25).
     *
     * Waiting is what parallelises, so the pool is sized for latency and not
     * for cores. It is created per call and shut down with it — this runs on
     * the storage thread a few times a session, never in a loop.
     */
    private fun describeAll(files: List<Pair<SafFile, String?>>): List<Map<String, Any>> {
        return mapInParallel(files, BOUNDS_READERS) { (file, tag) -> describe(file, tag) }
    }

    /**
     * One image's row, or null for a file tela did not write.
     *
     * The name is the identity, exactly as it is in the app-private tier: a
     * file whose name does not parse has no source and no id to report, and
     * this is a folder inside the user's own tree where anything at all may
     * have been dropped.
     */
    private fun describe(file: SafFile, tag: String?): Map<String, Any>? {
        val key = ImageFileNaming.keyOf(file.name) ?: return null
        val (width, height) = pixelBounds(file.uri)
        val row = mutableMapOf<String, Any>(
            "ref" to key,
            "location" to file.uri.toString(),
            "savedAt" to file.modifiedAt,
            "sizeBytes" to file.sizeBytes,
            "width" to width,
            "height" to height,
            // The one field [PrivateTierListing] never has to send: its rows are
            // always app-private, and these are always the files tier. Dart
            // routes deletes and retags by it, so an absent tier here would send
            // a document URI down the app-private delete path.
            "tier" to "filesOutsideGallery",
        )
        if (tag != null) row["tag"] = tag
        return row
    }

    /**
     * Reads a document's pixel dimensions without decoding its pixels.
     *
     * The stream twin of [PrivateTierListing.pixelBounds]: a SAF document has no
     * path for `decodeFile` to take, so the header is read through the resolver
     * instead. A corrupt or unreachable file answers -1, which Dart renders as a
     * safe broken-image state rather than dividing by an unknown dimension.
     */
    private fun pixelBounds(document: Uri): Pair<Int, Int> {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        return try {
            context.contentResolver.openInputStream(document)?.use { input ->
                BitmapFactory.decodeStream(input, null, options)
            }
            options.outWidth to options.outHeight
        } catch (_: Exception) {
            -1 to -1
        }
    }

    private companion object {
        /**
         * How many headers are read at once. Eight covers the binder latency
         * without asking the provider for more parallelism than it gives.
         */
        const val BOUNDS_READERS = 8
    }
}
