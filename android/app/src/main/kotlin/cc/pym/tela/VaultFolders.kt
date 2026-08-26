package cc.pym.tela

/**
 * The hidden directory explicit images go to inside a granted tree.
 *
 * The files-outside-gallery tier writes safe downloads to `tela/`, where the
 * user can find them. Explicit ones go beside it into a **dot-prefixed sibling**
 * — `.tela` by default — so a file manager listing the granted folder shows one
 * directory, not two, until someone deliberately turns hidden files on.
 *
 * **This is concealment, not security, and the difference matters.** A dot is a
 * convention every file manager can switch off, and a card is readable in any
 * other device. What actually holds is the rule above it: nothing here is ever
 * MediaStore-indexed, in any tier, so these files never reach Photos however
 * they are stored. The vault is what keeps them out of casual sight, which is
 * the thing the owner asked for (2026-08-25).
 *
 * A **label**, not a path: the caller names `tela` and the dot is added here.
 * That is what makes the dot un-droppable and un-doubleable — a user who types
 * `.stash` into the settings field gets `.stash`, and one who types `stash`
 * gets the same thing, because neither of them is composing the directory name.
 *
 * ```
 * VaultFolders.directoryOf("tela")   // ".tela"
 * VaultFolders.isValidLabel("..")    // false
 * ```
 */
object VaultFolders {
    /** The label used until the user picks another. */
    const val DEFAULT_LABEL = "tela"

    /**
     * Whether [label] may name a vault.
     *
     * The **same allowlist [TagFolders.isValid] applies**, deliberately, and for
     * the same reason: this crosses a method channel and becomes a directory
     * name, so `..` and a separator must be unreachable. The dot that makes the
     * directory hidden is added by [directoryOf] and is never part of the label,
     * which is what lets that guard stay exactly as strict as the tag one.
     */
    fun isValidLabel(label: String): Boolean = TagFolders.isValid(label)

    /**
     * The directory [label] names, or null when it names none.
     *
     * Null rather than a repaired name, matching every other guard on this side:
     * a label this refuses is a settings write that failed, not a folder to
     * invent.
     */
    fun directoryOf(label: String): String? {
        if (!isValidLabel(label)) return null
        return ".$label"
    }
}

/**
 * Where the files-outside-gallery tier writes: the granted tree, and the label
 * of the hidden folder inside it that explicit images go to.
 *
 * One value rather than two parameters threaded through [TierWriting],
 * [SafDocuments] and the listing, because they are one answer to one question
 * and a call site holding the tree without the vault would silently write an
 * explicit image into the visible folder.
 */
data class OutsideGalleryTarget(
    val tree: String?,
    val vaultLabel: String = VaultFolders.DEFAULT_LABEL,
) {
    /** The hidden directory's name, or null when the label is not usable. */
    val vaultDirectory: String? get() = VaultFolders.directoryOf(vaultLabel)
}
