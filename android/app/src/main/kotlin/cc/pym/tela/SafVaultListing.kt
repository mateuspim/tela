package cc.pym.tela

import android.content.Context
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
        return (untagged(vault) + tagged(vault))
            .mapNotNull { (file, tag) -> describe(file, tag) }
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
     * One image's row, or null for a file tela did not write.
     *
     * The name is the identity, exactly as it is in the app-private tier: a
     * file whose name does not parse has no source and no id to report, and
     * this is a folder inside the user's own tree where anything at all may
     * have been dropped.
     *
     * **Carries no pixel bounds.** This used to open every file to decode its
     * header — 1150 header reads straight off the disk take 1.5s, but the same
     * files through this provider ran at about eleven a second even eight at a
     * time, because the cost is the binder round trip per file, not the card.
     * On a vault of a few thousand that was tens of seconds of nothing on
     * screen, paid again on every refresh. `width`/`height` are simply absent
     * now — Dart's mapper already reads a missing one as unknown, the same
     * reading it gives a corrupt file — and a grid tile asks for its own bounds
     * lazily instead, through `LocalPreviewCache.materializeThumbnail`, only
     * once it is actually on screen.
     */
    private fun describe(file: SafFile, tag: String?): Map<String, Any>? {
        val key = ImageFileNaming.keyOf(file.name) ?: return null
        val row = mutableMapOf<String, Any>(
            "ref" to key,
            "location" to file.uri.toString(),
            "savedAt" to file.modifiedAt,
            "sizeBytes" to file.sizeBytes,
            // The one field [PrivateTierListing] never has to send: its rows are
            // always app-private, and these are always the files tier. Dart
            // routes deletes and retags by it, so an absent tier here would send
            // a document URI down the app-private delete path.
            "tier" to "filesOutsideGallery",
        )
        if (tag != null) row["tag"] = tag
        return row
    }
}
