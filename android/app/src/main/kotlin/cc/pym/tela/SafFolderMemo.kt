package cc.pym.tela

import android.net.Uri

/**
 * Short-lived memory of which tag folders a tela folder holds.
 *
 * The one-wallpaper-one-tag sweep ([SafDocuments.dropFromOtherFolders]) needs
 * the tag folders of the tela root for **every file** it writes, and listing
 * the root costs a binder round trip per row on a card. Offloading N images
 * into a root of M entries was N×M rows — the likely "move to SD hangs".
 *
 * Process-wide because [ImageStorage] is built per channel call, so an
 * instance field would be forgotten between two files of the same batch. A
 * stale entry is harmless by construction: the sweep probes each folder it
 * gets, so a deleted folder is a miss, and the only thing a *missing* entry
 * costs is a stale near-copy surviving until the memo lapses — tela's own folder
 * creations call [forget], so that can only come from another app.
 *
 * ```
 * SafFolderMemo.remember(telaFolder, folders)
 * SafFolderMemo.recall(telaFolder)
 * ```
 */
internal object SafFolderMemo {
    private const val LIFETIME_MS = 30_000L
    private val entries = HashMap<String, Pair<Long, List<Uri>>>()

    /** The folders last remembered for [parent], or null once they lapsed. */
    @Synchronized
    fun recall(parent: Uri, now: Long = System.currentTimeMillis()): List<Uri>? {
        val (at, folders) = entries[parent.toString()] ?: return null
        return if (now - at <= LIFETIME_MS) folders else null
    }

    /** Remembers [folders] as the tag folders of [parent]. */
    @Synchronized
    fun remember(parent: Uri, folders: List<Uri>, now: Long = System.currentTimeMillis()) {
        entries[parent.toString()] = now to folders
    }

    /** Drops [parent]'s entry; call when tela itself adds a folder to it. */
    @Synchronized
    fun forget(parent: Uri) {
        entries.remove(parent.toString())
    }

    /** Drops everything. For tests, which share this process. */
    @Synchronized
    fun clear() {
        entries.clear()
    }
}
