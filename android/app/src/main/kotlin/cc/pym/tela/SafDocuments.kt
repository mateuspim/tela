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

    /** The child of [parent] called [name], or null if it has none. */
    fun findChild(context: Context, parent: Uri, name: String): Uri? {
        val resolver = context.contentResolver
        val childDocuments = DocumentsContract.buildChildDocumentsUriUsingTree(
            parent,
            DocumentsContract.getDocumentId(parent),
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        )
        resolver.query(childDocuments, projection, null, null, null)?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            )
            val nameColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            )
            while (cursor.moveToNext()) {
                if (cursor.getString(nameColumn) == name) {
                    return DocumentsContract.buildDocumentUriUsingTree(
                        parent,
                        cursor.getString(idColumn),
                    )
                }
            }
        }
        return null
    }

    private fun findOrCreateDirectory(context: Context, parent: Uri, name: String): Uri? {
        return findChild(context, parent, name) ?: DocumentsContract.createDocument(
            context.contentResolver,
            parent,
            DocumentsContract.Document.MIME_TYPE_DIR,
            name,
        )
    }
}
