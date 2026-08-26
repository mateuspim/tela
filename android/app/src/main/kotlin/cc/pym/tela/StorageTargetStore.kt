package cc.pym.tela

import android.content.Context

/**
 * Where the files tier writes right now, read straight from storage.
 *
 * **Extracted so the rotation worker can ask the same question the channel
 * does.** The granted SAF tree and the vault label live in native preferences,
 * not on the Dart side — so a worker running with no Dart alive has to read
 * them here, and passing copies down through a scheduled job's input data would
 * freeze whatever was true on the day the schedule was made. A user who moves
 * their vault afterwards would have a rotation quietly reading the old folder.
 *
 * ```
 * val target = StorageTargetStore.target(context)
 * ```
 */
internal object StorageTargetStore {
    /** The preferences file [ImageStoreChannel] writes these into. */
    private const val PREFERENCES = "tela.storage"
    private const val OUTSIDE_GALLERY_TREE = "outsideGalleryTree"
    private const val VAULT_LABEL = "vaultLabel"

    /** The granted tree URI, or null when nothing has been granted. */
    fun tree(context: Context): String? = preferences(context)
        .getString(OUTSIDE_GALLERY_TREE, null)

    /**
     * The vault label, falling back to the default for a missing **or
     * unusable** one.
     *
     * The second half matters: a preferences file is editable on a rooted
     * device and survives a downgrade, so the value read here is not
     * necessarily one tela wrote.
     */
    fun vaultLabel(context: Context): String {
        val stored = preferences(context).getString(VAULT_LABEL, null)
        if (stored == null || !VaultFolders.isValidLabel(stored)) {
            return VaultFolders.DEFAULT_LABEL
        }
        return stored
    }

    /** Both halves, as the one value every writer and listing takes. */
    fun target(context: Context): OutsideGalleryTarget =
        OutsideGalleryTarget(tree(context), vaultLabel(context))

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
}
