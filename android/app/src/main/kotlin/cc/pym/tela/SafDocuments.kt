package cc.pym.tela

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract

/**
 * Finding and creating documents inside a tree the user granted.
 *
 * Only the `filesOutsideGallery` tier goes through here — it is the one tier
 * whose directory tela does not own and cannot address by path. Every lookup is
 * a `ContentResolver` query against the tree's child documents, which is why it
 * is worth keeping apart from the tier writer that calls it.
 *
 * ```
 * val directory = SafDocuments.telaFolderIn(context, tree) ?: return
 * SafDocuments.ensureNoMediaMarker(context, directory)
 * ```
 */
/** One entry of a SAF directory listing, as [SafDocuments] reads it back. */
private data class SafChild(val id: String, val name: String, val mimeType: String?)

internal object SafDocuments {
    /** The provider a granted tree must belong to; anything else is refused. */
    private const val EXTERNAL_STORAGE_PROVIDER = "com.android.externalstorage.documents"

    /** tela's own folder inside [tree], created on first use. */
    fun telaFolderIn(context: Context, tree: Uri): Uri? {
        if (tree.authority != EXTERNAL_STORAGE_PROVIDER) return null
        val root = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        return findOrCreateDirectory(context, root, TreeLocation.TELA_FOLDER)
    }

    /**
     * The tag's folder inside [telaFolder], created on first use, or
     * [telaFolder] itself for an untagged download.
     *
     * Null for a tag that fails [TagFolders.isValid] — the same refusal
     * [TagFolders.privateDirectory] answers, arriving by the other tier's door.
     * SAF names documents rather than paths, so a `..` could not traverse here
     * the way it could on a real file system; it is refused anyway, because a
     * guard that holds only on the tier that happens to need it is a guard
     * somebody will move.
     */
    fun tagFolderIn(context: Context, telaFolder: Uri, tag: String?): Uri? {
        if (tag == null) return telaFolder
        if (!TagFolders.isValid(tag)) return null
        return findOrCreateDirectory(context, telaFolder, tag)
    }

    /**
     * Writes the `.nomedia` marker that keeps this tier out of the gallery
     * index, unless one is already there.
     */
    fun ensureNoMediaMarker(context: Context, directory: Uri): Boolean {
        if (findChild(context, directory, ".nomedia") != null) return true
        return DocumentsContract.createDocument(
            context.contentResolver,
            directory,
            "application/octet-stream",
            ".nomedia",
        ) != null
    }

    /**
     * Which folder under [telaFolder] currently holds [document], or null.
     *
     * `DocumentsContract.moveDocument` wants the document's present parent and a
     * document URI does not carry one, so it is found by asking: the tela folder
     * itself first, then each tag folder inside it. Bounded by how many tags the
     * user has made, and only ever walked for a retag they asked for — the
     * alternative is recording a parent beside every stored location for the one
     * operation that needs it.
     *
     * Compares document ids rather than URIs: the same document reached through
     * a listing and through a tree build can differ in URI form while naming the
     * same file, and it is the id that identifies it.
     */
    fun parentOf(context: Context, telaFolder: Uri, document: Uri): Uri? {
        val wanted = DocumentsContract.getDocumentId(document)
        if (childIds(context, telaFolder).contains(wanted)) return telaFolder
        return directoriesIn(context, telaFolder).firstOrNull { folder ->
            childIds(context, folder).contains(wanted)
        }
    }

    /** The child of [parent] called [name], or null if it has none. */
    fun findChild(context: Context, parent: Uri, name: String): Uri? {
        val match = childrenOf(context, parent).firstOrNull { it.name == name } ?: return null
        return DocumentsContract.buildDocumentUriUsingTree(parent, match.id)
    }

    /** The document ids directly inside [parent]. */
    private fun childIds(context: Context, parent: Uri): Set<String> =
        childrenOf(context, parent).mapTo(mutableSetOf()) { it.id }

    /** The subdirectories of [parent], as document URIs. */
    private fun directoriesIn(context: Context, parent: Uri): List<Uri> {
        return childrenOf(context, parent)
            .filter { it.mimeType == DocumentsContract.Document.MIME_TYPE_DIR }
            .map { DocumentsContract.buildDocumentUriUsingTree(parent, it.id) }
    }

    /** One listing of [parent]'s children — the single cursor walk above three
     *  questions, so a projection or a column name has one spelling. */
    private fun childrenOf(context: Context, parent: Uri): List<SafChild> {
        val childDocuments = DocumentsContract.buildChildDocumentsUriUsingTree(
            parent,
            DocumentsContract.getDocumentId(parent),
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        val children = mutableListOf<SafChild>()
        context.contentResolver
            .query(childDocuments, projection, null, null, null)
            ?.use { cursor -> while (cursor.moveToNext()) children += cursor.readChild() }
        return children
    }

    private fun android.database.Cursor.readChild(): SafChild = SafChild(
        id = getString(getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)),
        name = getString(getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)),
        mimeType = getString(getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)),
    )

    private fun findOrCreateDirectory(context: Context, parent: Uri, name: String): Uri? {
        return findChild(context, parent, name) ?: DocumentsContract.createDocument(
            context.contentResolver,
            parent,
            DocumentsContract.Document.MIME_TYPE_DIR,
            name,
        )
    }
}
