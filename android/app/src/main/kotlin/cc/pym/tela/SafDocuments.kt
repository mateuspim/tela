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
private data class SafChild(
    val id: String,
    val name: String,
    val mimeType: String?,
    val sizeBytes: Long,
    val modifiedAt: Long,
)

/** One file inside a granted tree, with the stats a listing reports. */
data class SafFile(
    val uri: Uri,
    val name: String,
    val sizeBytes: Long,
    val modifiedAt: Long,
)

internal object SafDocuments {
    /** The provider a granted tree must belong to; anything else is refused. */
    private const val EXTERNAL_STORAGE_PROVIDER = "com.android.externalstorage.documents"

    /** The marker this tier writes, and the one file a listing must never show. */
    private const val NO_MEDIA_MARKER = ".nomedia"

    /**
     * tela's own folder inside [tree], created on first use — or [tree] itself
     * when the user granted a folder already called `tela` (device pass F4).
     */
    fun telaFolderIn(context: Context, tree: Uri): Uri? {
        if (TreeLocation.of(tree)?.isTelaFolder != true) {
            return folderIn(context, tree, TreeLocation.TELA_FOLDER)
        }
        // A build before F4 nested `tela/tela/` here. Keep that layout where it
        // exists, or every download already in it is re-read as a tag folder
        // called "tela" and the next download of one lands beside it twice.
        return existingFolderIn(context, tree, TreeLocation.TELA_FOLDER) ?: rootOf(tree)
    }

    /**
     * The hidden folder explicit images go to inside [tree], created on first
     * use, or null when [target] names no usable vault.
     *
     * A **sibling** of the visible `tela/`, not a child of it. Both are inside
     * the tree the user granted, so a sync tool pointed at that tree still
     * reaches both — what changes is what a file manager shows when it lists the
     * granted folder, which is the whole point of the dot.
     */
    fun vaultFolderIn(context: Context, tree: Uri, target: OutsideGalleryTarget): Uri? {
        val name = target.vaultDirectory ?: return null
        return folderIn(context, tree, name)
    }

    /** A directly-named directory inside [tree], created on first use. */
    private fun folderIn(context: Context, tree: Uri, name: String): Uri? {
        val root = rootOf(tree) ?: return null
        return findOrCreateDirectory(context, root, name)
    }

    /** [tree]'s own top document, or null for a tree from another provider. */
    private fun rootOf(tree: Uri): Uri? {
        if (tree.authority != EXTERNAL_STORAGE_PROVIDER) return null
        return DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
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
        if (findChild(context, directory, NO_MEDIA_MARKER) != null) return true
        return DocumentsContract.createDocument(
            context.contentResolver,
            directory,
            "application/octet-stream",
            NO_MEDIA_MARKER,
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

    /**
     * The child of [parent] called [name], or null if it has none.
     *
     * **Case-insensitive**, on purpose: this queries removable storage, which is
     * case-insensitive at the medium (exFAT/FAT32) even where the SAF layer
     * above it is not. A case-sensitive `==` here — the original bug, found on
     * device 2026-08-26 — let `tagFolderIn` ask for `"alcololi"`, miss an
     * existing `"Alcololi"`, and create another folder; `DocumentsContract`
     * renames the collision to `"alcololi (1)"` rather than refusing it, so
     * every mismatched retry silently grew a new folder instead of failing
     * loud. After 32 of those, Android's own uniquifier exhausts its retry
     * budget and starts throwing `FileNotFoundException("Failed to create
     * unique file")` — which is where this was actually noticed, as a stuck
     * offload, not as a duplicate-folder problem. Matching case-insensitively
     * finds the one real folder regardless of how a caller cased the name, so
     * no new collision is ever manufactured in the first place.
     */
    fun findChild(context: Context, parent: Uri, name: String): Uri? {
        val match =
            childrenOf(context, parent).firstOrNull { it.name.equals(name, ignoreCase = true) }
                ?: return null
        return DocumentsContract.buildDocumentUriUsingTree(parent, match.id)
    }

    /**
     * Deletes [name] from every tag folder under [telaFolder] except [keep].
     *
     * One wallpaper, one tag — the SAF half of the rule
     * [TierWriting.dropOtherPrivateTags] states in full: re-downloading
     * something you already have, under a different tag, means "file it there",
     * not "keep two of it". This tier is the desktop-sync path, where a folder
     * quietly accumulating near-copies is worse than anywhere else.
     *
     * Failures are ignored one document at a time. A copy on a card that has
     * been unmounted, or under a grant that has been narrowed, is not a reason
     * to fail a download that has already landed.
     */
    fun dropFromOtherFolders(context: Context, telaFolder: Uri, keep: Uri, name: String) {
        val folders = listOf(telaFolder) + directoriesIn(context, telaFolder)
        for (folder in folders.filter { it != keep }) {
            val stale = findChild(context, folder, name) ?: continue
            try {
                DocumentsContract.deleteDocument(context.contentResolver, stale)
            } catch (_: Exception) {
                continue
            }
        }
    }

    /**
     * The image files directly inside [parent], with the stats a listing needs.
     *
     * Directories and the `.nomedia` marker are dropped here rather than by the
     * caller: every caller wants the same two gone, and a listing that leaked
     * the marker would report a zero-byte image whose name parses as nothing.
     */
    fun filesIn(context: Context, parent: Uri): List<SafFile> {
        return childrenOf(context, parent)
            .filter { it.mimeType != DocumentsContract.Document.MIME_TYPE_DIR }
            .filter { it.name != NO_MEDIA_MARKER }
            .map { child ->
                SafFile(
                    uri = DocumentsContract.buildDocumentUriUsingTree(parent, child.id),
                    name = child.name,
                    sizeBytes = child.sizeBytes,
                    modifiedAt = child.modifiedAt,
                )
            }
    }

    /** The subdirectories of [parent], as document URIs paired with their names. */
    fun subdirectoriesOf(context: Context, parent: Uri): List<Pair<String, Uri>> {
        return childrenOf(context, parent)
            .filter { it.mimeType == DocumentsContract.Document.MIME_TYPE_DIR }
            .map { it.name to DocumentsContract.buildDocumentUriUsingTree(parent, it.id) }
    }

    /** The child of [parent] called [name], **only if it already exists**. */
    fun existingFolderIn(context: Context, tree: Uri, name: String): Uri? {
        val root = rootOf(tree) ?: return null
        return findChild(context, root, name)
    }

    /** The document ids directly inside [parent]. */
    private fun childIds(context: Context, parent: Uri): Set<String> =
        childrenOf(context, parent).mapTo(mutableSetOf()) { it.id }

    /**
     * The tag folders of [parent], as document URIs.
     *
     * Hidden directories are skipped: no tag folder can be one
     * ([TagFolders.isValid]), and once a granted `tela` folder is the tela
     * folder itself (F4) the `.tela` vault is a child of it — a walk that
     * stepped in could move or delete an explicit file on a safe one's behalf.
     */
    private fun directoriesIn(context: Context, parent: Uri): List<Uri> {
        return childrenOf(context, parent)
            .filter { it.mimeType == DocumentsContract.Document.MIME_TYPE_DIR }
            .filterNot { it.name.startsWith(".") }
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
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
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
        // Both are optional columns a provider may leave null, and neither is
        // worth dropping a row over: an unknown size sorts as zero and an
        // unknown date sorts oldest, where a null would crash the walk.
        sizeBytes = longOrZero(DocumentsContract.Document.COLUMN_SIZE),
        modifiedAt = longOrZero(DocumentsContract.Document.COLUMN_LAST_MODIFIED),
    )

    private fun android.database.Cursor.longOrZero(column: String): Long {
        val at = getColumnIndex(column)
        if (at < 0 || isNull(at)) return 0L
        return getLong(at)
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
