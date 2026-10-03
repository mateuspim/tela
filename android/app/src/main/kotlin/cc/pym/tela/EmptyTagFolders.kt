package cc.pym.tela

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File

/**
 * Removes a tag folder once deleting its last wallpaper has emptied it.
 *
 * Deleting every wallpaper of a tag left its folder behind — an empty
 * `minimalism/` on the desktop-sync path that no tela screen shows and nothing
 * would ever fill again (device pass F9, 2026-10-03). Only ever a **tag**
 * folder: the tela folder itself, the vault and the granted tree are where the
 * next download lands, so they stay however empty they get.
 *
 * ```kotlin
 * EmptyTagFolders.pruneAfterPrivate(context, deletedFile)
 * EmptyTagFolders.pruneAfterDocument(context, deletedDocument)
 * ```
 */
internal object EmptyTagFolders {
    /** The marker the files tier writes into each folder; it holds no wallpaper. */
    private const val NO_MEDIA_MARKER = ".nomedia"

    /** Deletes the private tag folder [file] sat in, if that left it empty. */
    fun pruneAfterPrivate(context: Context, file: File) {
        val folder = file.parentFile ?: return
        val root = TelaDirectories.privateImages(context).canonicalFile
        if (folder.canonicalFile.parentFile != root) return
        if (folder.list()?.isEmpty() == true) folder.delete()
    }

    /**
     * Deletes the SAF tag folder [document] sat in, if all that is left in it
     * is tela's own `.nomedia` marker.
     *
     * Checked first, because `deleteDocument` on a directory takes everything
     * in it — a file the user dropped into a tag folder by hand must keep it.
     * Failures are ignored: the wallpaper is already gone, which is what the
     * user asked for, and a leftover folder is not a reason to say otherwise.
     */
    fun pruneAfterDocument(context: Context, document: Uri) {
        val folder = tagFolderOf(document) ?: return
        try {
            if (!holdsOnlyMarker(context, folder)) return
            DocumentsContract.deleteDocument(context.contentResolver, folder)
        } catch (_: Exception) {
            return
        }
    }

    /**
     * Whether [folder] is a tag folder of a files tier granted [tree].
     *
     * One level inside the tela folder, which is the tree's `tela` child — or
     * the tree itself when the user granted a folder already called `tela`
     * (F4). The vault's tags sit at the same depth as a sibling of `tela/`.
     * Never a hidden folder: no tag can be one ([TagFolders.isValid]).
     *
     * ```kotlin
     * isTagFolder(TreeLocation("1A2B", "Wallpapers"), TreeLocation("1A2B", "Wallpapers/tela/anime"))  // true
     * isTagFolder(TreeLocation("1A2B", "Wallpapers"), TreeLocation("1A2B", "Wallpapers/tela"))        // false
     * ```
     */
    fun isTagFolder(tree: TreeLocation, folder: TreeLocation): Boolean {
        if (folder.volumeId != tree.volumeId) return false
        val prefix = if (tree.relativePath.isEmpty()) "" else "${tree.relativePath}/"
        if (!folder.relativePath.startsWith(prefix)) return false
        val inside = folder.relativePath.removePrefix(prefix).split('/')
        val depth = if (tree.isTelaFolder) 1 else 2
        val name = inside.last()
        return inside.size == depth && name.isNotEmpty() && !name.startsWith(".")
    }

    /**
     * The tag folder holding [document], or null when it sits loose in the tela
     * folder, or [document] is not a tree document at all.
     *
     * Read off the document id rather than asked of the provider: the external
     * storage provider names a document by its path ([TreeLocation]), so the
     * parent costs no binder call — and after the delete, nothing is left to ask.
     */
    private fun tagFolderOf(document: Uri): Uri? {
        val (treeId, documentId) = try {
            DocumentsContract.getTreeDocumentId(document) to
                DocumentsContract.getDocumentId(document)
        } catch (_: IllegalArgumentException) {
            return null
        }
        val parentId = documentId.substringBeforeLast('/', missingDelimiterValue = "")
        val tree = TreeLocation.parse(treeId) ?: return null
        val parent = TreeLocation.parse(parentId) ?: return null
        if (!isTagFolder(tree, parent)) return null
        return DocumentsContract.buildDocumentUriUsingTree(document, parentId)
    }

    private fun holdsOnlyMarker(context: Context, folder: Uri): Boolean =
        SafDocuments.childNamesOf(context, folder).all { it == NO_MEDIA_MARKER }
}
