package cc.pym.tela

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import java.io.File
import java.util.Locale

/**
 * An in-memory stand-in for ExternalStorageProvider, registered under its real
 * authority so [SafDocuments] cannot tell the difference.
 *
 * Mirrors the four behaviours the SAF code depends on, each of which was
 * learned on a device: ids are `<parent id>/<name>` (no slash under a volume
 * root ending in `:`), lookups are **case-insensitive** like the FAT-family
 * card, a clash is **renamed** to `name (1)` rather than refused, and a query
 * for a document that is not there answers a null cursor.
 *
 * [queries] counts every cursor handed out, split into single-document probes
 * and child listings, so a test can assert the cost of an operation — which is
 * what the offload fix is about — and not only its result.
 */
class FakeDocumentsProvider(private val storage: File) : ContentProvider() {
    class Node(val id: String, val name: String, val isDir: Boolean, val file: File?)

    private val nodes = LinkedHashMap<String, Node>()
    var listings = 0
        private set
    var probes = 0
        private set

    /** Zeroes the query counters, e.g. after a test's fixture is laid out. */
    fun resetCounts() {
        listings = 0
        probes = 0
    }

    /** Adds the folder [id] (and says nothing about its parents). */
    fun folder(id: String) {
        nodes[key(id)] = Node(id, id.substringAfterLast('/').substringAfterLast(':'), true, null)
    }

    /** Adds a file [id] holding [text]. */
    fun file(id: String, text: String = "pixels") {
        nodes[key(id)] = newFile(id).also { it.file!!.writeText(text) }
    }

    /** The names (not ids) directly under [parentId]. */
    fun namesUnder(parentId: String): List<String> = childrenOf(parentId).map { it.name }

    /** The text of the file [id], or null if it does not exist. */
    fun textOf(id: String): String? = nodes[key(id)]?.file?.readText()

    private fun key(id: String) = id.lowercase(Locale.ROOT)

    private fun newFile(id: String) =
        Node(id, id.substringAfterLast('/').substringAfterLast(':'), false,
            File(storage, "doc-${nodes.size}-${System.nanoTime()}"))

    private fun childrenOf(parentId: String): List<Node> {
        val prefix = if (parentId.endsWith(":")) parentId else "$parentId/"
        return nodes.values.filter {
            it.id.startsWith(prefix, ignoreCase = true) && !it.id.drop(prefix.length).contains('/')
        }
    }

    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? {
        val columns = projection ?: arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
        val id = DocumentsContract.getDocumentId(uri)
        val cursor = MatrixCursor(columns)
        if (uri.pathSegments.last() == "children") {
            listings++
            childrenOf(id).forEach { cursor.addRow(row(it, columns)) }
            return cursor
        }
        probes++
        val node = nodes[key(id)] ?: return null
        return cursor.also { it.addRow(row(node, columns)) }
    }

    private fun row(node: Node, columns: Array<out String>): Array<Any?> = columns.map {
        when (it) {
            DocumentsContract.Document.COLUMN_DOCUMENT_ID -> node.id
            DocumentsContract.Document.COLUMN_DISPLAY_NAME -> node.name
            DocumentsContract.Document.COLUMN_MIME_TYPE ->
                if (node.isDir) DocumentsContract.Document.MIME_TYPE_DIR else "image/jpeg"
            DocumentsContract.Document.COLUMN_SIZE -> node.file?.length() ?: 0L
            else -> 0L
        }
    }.toTypedArray()

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle? {
        val target = Uri.parse(extras!!.getString("uri"))
        val id = DocumentsContract.getDocumentId(target)
        return when (method) {
            "android:createDocument" -> create(target, id, extras)
            "android:deleteDocument" -> {
                nodes.remove(key(id))
                Bundle()
            }
            else -> null
        }
    }

    private fun create(parent: Uri, parentId: String, extras: Bundle): Bundle {
        val wanted = extras.getString("_display_name")!!
        val isDir = extras.getString("mime_type") == DocumentsContract.Document.MIME_TYPE_DIR
        val stem = if (parentId.endsWith(":")) parentId else "$parentId/"
        var name = wanted
        var n = 0
        while (nodes.containsKey(key(stem + name))) name = "$wanted (${++n})"
        if (isDir) folder(stem + name) else nodes[key(stem + name)] = newFile(stem + name)
        val made = DocumentsContract.buildDocumentUriUsingTree(parent, stem + name)
        return Bundle().apply { putParcelable("uri", made) }
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val node = nodes[key(DocumentsContract.getDocumentId(uri))]!!
        val flags = ParcelFileDescriptor.parseMode(mode)
        return ParcelFileDescriptor.open(node.file!!, flags)
    }

    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ) = 0
}
