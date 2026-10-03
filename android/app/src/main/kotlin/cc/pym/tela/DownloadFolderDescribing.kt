package cc.pym.tela

import android.content.Context
import android.net.Uri
import android.os.Environment
import android.os.storage.StorageVolume
import android.provider.DocumentsContract
import android.system.Os

/**
 * A granted tree split into the volume it lives on and the path inside it.
 *
 * SAF hands out document ids shaped `volume:path` — `primary:Pictures/tela` on
 * built-in storage, `1A2B-3C4D:Wallpapers` on a card, whose left half is the
 * card's own uuid. Everything downstream needs those two halves apart, and this
 * is the only place that knows the shape.
 */
data class TreeLocation(val volumeId: String, val relativePath: String) {
    /** Whether this is the device's built-in shared storage. */
    val isPrimary: Boolean get() = volumeId == PRIMARY_VOLUME

    /**
     * Whether the granted folder is itself called `tela`, so the tier writes
     * into it rather than nesting a second one.
     *
     * Granting a folder made for tela and finding the files in `tela/tela/` was
     * device pass F4 (2026-10-03). Case-insensitive, as shared storage is.
     */
    val isTelaFolder: Boolean
        get() = relativePath.substringAfterLast('/').equals(TELA_FOLDER, ignoreCase = true)

    /**
     * Where the files-outside-gallery tier actually writes inside this tree.
     *
     * The tier appends its own `tela` child to whatever folder the user granted
     * — unless that folder already is one, see [isTelaFolder] — so this, not
     * [relativePath], is the directory to show the user, to guard, and to
     * compare against another tier's.
     */
    val telaFolderPath: String
        get() = when {
            relativePath.isEmpty() -> TELA_FOLDER
            isTelaFolder -> relativePath
            else -> "$relativePath/$TELA_FOLDER"
        }

    /**
     * Whether the files tier here would share a directory with the gallery tier.
     *
     * **The two tiers are only ever distinct by convention.** One is
     * MediaStore-indexed and the other carries a `.nomedia`, but on disk that is
     * a property of the *directory*, not of the tier — so one tier can reach into
     * the other's and flip it. Granting `Pictures` at the folder prompt (the
     * obvious pick, and the one left after the SAF picker refuses storage root)
     * resolves this tier onto `Pictures/tela`, which is the gallery tier's own
     * folder; tela then adopts it and marks it `.nomedia`, and every wallpaper
     * ever downloaded to the gallery — plus whatever else the user kept there —
     * disappears from Photos and every gallery app at once. Nothing is deleted,
     * which is exactly what made it hard to see (owner, 2026-07-28).
     *
     * Overlap is refused in **both** directions, because a `.nomedia` in a
     * directory tela does not exclusively own affects the whole folder and
     * outlives the app. Only the primary volume can collide: the gallery tier
     * inserts into `MediaStore.Images.Media.EXTERNAL_CONTENT_URI`, which is that
     * volume, so a card's own `Pictures/tela` is nobody else's directory.
     *
     * ```kotlin
     * TreeLocation.parse("primary:Pictures")?.overlapsGallery  // true
     * TreeLocation.parse("primary:Download")?.overlapsGallery  // false
     * ```
     */
    val overlapsGallery: Boolean
        get() {
            if (!isPrimary) return false
            // Shared storage is case-insensitive, so `pictures` is `Pictures`.
            val ours = telaFolderPath.lowercase()
            val gallery = GALLERY_FOLDER_PATH.lowercase()
            return ours == gallery ||
                ours.startsWith("$gallery/") ||
                gallery.startsWith("$ours/")
        }

    companion object {
        const val PRIMARY_VOLUME = "primary"

        /** The child every tier of tela's writes into, under its own root. */
        const val TELA_FOLDER = "tela"

        /**
         * The gallery tier's directory, spelled as MediaStore's `RELATIVE_PATH`
         * does. The one definition, so the guard above cannot drift from the
         * folder [ImageStorage] actually writes to.
         */
        val GALLERY_FOLDER_PATH = "${Environment.DIRECTORY_PICTURES}/$TELA_FOLDER"

        /**
         * The location a granted SAF tree names, or null when it names none.
         *
         * [parse]'s companion for callers holding the tree URI rather than its
         * document id — and, unlike `DocumentsContract.getTreeDocumentId`, it
         * answers null for a URI that is not a tree instead of throwing. Both
         * of its callers guard a folder on the answer and one of them runs on
         * the main thread, so a throw here would be a crash.
         *
         * ```kotlin
         * TreeLocation.of(Uri.parse("content://…/tree/primary%3APictures"))
         * // TreeLocation("primary", "Pictures")
         * ```
         */
        fun of(tree: Uri): TreeLocation? {
            val documentId = try {
                DocumentsContract.getTreeDocumentId(tree)
            } catch (_: IllegalArgumentException) {
                return null
            }
            return parse(documentId)
        }

        /**
         * Splits a SAF tree document id, or null when it is not one.
         *
         * ```kotlin
         * TreeLocation.parse("1A2B-3C4D:Wallpapers/tela")
         * // TreeLocation("1A2B-3C4D", "Wallpapers/tela")
         * ```
         */
        fun parse(documentId: String): TreeLocation? {
            val separator = documentId.indexOf(':')
            if (separator <= 0) return null
            return TreeLocation(
                volumeId = documentId.substring(0, separator),
                relativePath = documentId.substring(separator + 1).trim('/'),
            )
        }
    }
}

/**
 * Answers where the files-outside-gallery tier writes, for the settings screen.
 *
 * Read-only by design: describing a folder must never create, move or grant
 * one. Choosing is [MainActivity]'s job, because only an Activity can start the
 * picker.
 */
class DownloadFolderDescribing(private val context: Context) {

    /**
     * The location snapshot: whether a card is on offer, and the folder in use.
     *
     * "No folder yet" is a success with no `folder` key, not a failure — a tier
     * nobody has configured is an ordinary state the row draws as "not set", and
     * the `sdCardAvailable` flag is needed whether or not a folder exists.
     */
    fun describe(tree: String?): Map<String, Any> {
        val volumes = DownloadVolumes(context)
        val folder = folderOf(tree, volumes)
        val base = mapOf<String, Any>(
            "success" to true,
            "sdCardAvailable" to volumes.sdCardAvailable(),
        )
        return if (folder == null) base else base + mapOf("folder" to folder)
    }

    /**
     * Whether the granted [tree] can take a download right now.
     *
     * The store gate asks this to tell an ejected card (folderUnavailable) from
     * a tier that was never set up (notConfigured): both leave the same empty
     * destination, but the fix differs — reconnect versus choose. False for a
     * foreign or malformed tree, which names nothing writable. Settings surfaces
     * the same fact through [describe]'s `isAvailable`.
     */
    fun isAvailable(tree: String): Boolean {
        val uri = Uri.parse(tree)
        val location = treeLocationOf(uri) ?: return false
        return isAvailable(uri, DownloadVolumes(context).forLocation(location))
    }

    /** The granted folder as a payload, or null for none / an unusable tree. */
    private fun folderOf(tree: String?, volumes: DownloadVolumes): Map<String, Any>? {
        val uri = tree?.let(Uri::parse) ?: return null
        val location = treeLocationOf(uri) ?: return null
        val volume = volumes.forLocation(location)
        return mapOf(
            "volumeLabel" to (volume?.getDescription(context) ?: fallbackLabel(location)),
            // The tier writes into a "tela" child of the granted tree, so that
            // is the path to show — not the folder the user pointed at.
            "relativePath" to location.telaFolderPath,
            "isRemovable" to (volume?.isRemovable ?: !location.isPrimary),
            "isAvailable" to isAvailable(uri, volume),
        ) + freeBytesOf(uri)
    }

    private fun treeLocationOf(tree: Uri): TreeLocation? {
        if (tree.authority != EXTERNAL_STORAGE_PROVIDER) return null
        val documentId = try {
            DocumentsContract.getTreeDocumentId(tree)
        } catch (_: IllegalArgumentException) {
            return null
        }
        return TreeLocation.parse(documentId)
    }

    /** Used only when the volume is gone and cannot name itself. */
    private fun fallbackLabel(location: TreeLocation): String =
        if (location.isPrimary) "Internal storage" else location.volumeId

    /**
     * Whether tela could write there right now.
     *
     * Both halves are required and neither implies the other: a mounted card
     * whose grant the system dropped is unusable, and a still-held grant to an
     * ejected card is equally unusable.
     */
    private fun isAvailable(tree: Uri, volume: StorageVolume?): Boolean {
        if (volume != null && volume.state != Environment.MEDIA_MOUNTED) return false
        return context.contentResolver.persistedUriPermissions.any {
            it.uri == tree && it.isWritePermission
        }
    }

    /**
     * Free space on the volume, omitted when it cannot be read.
     *
     * `fstatvfs` on a descriptor opened from the tree is the only route that
     * works here: SAF exposes no free-space API and no filesystem path, so
     * `StatFs` has nothing to stand on and `DocumentFile` never offers it.
     */
    private fun freeBytesOf(tree: Uri): Map<String, Any> {
        val document = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        return try {
            context.contentResolver.openFileDescriptor(document, "r").use { descriptor ->
                val stats = Os.fstatvfs(descriptor?.fileDescriptor ?: return emptyMap())
                mapOf("freeBytes" to stats.f_bavail * stats.f_frsize)
            }
        } catch (_: Exception) {
            emptyMap()
        }
    }

    private companion object {
        const val EXTERNAL_STORAGE_PROVIDER = "com.android.externalstorage.documents"
    }
}
