package cc.pym.tela

import android.content.Context
import java.io.File

/**
 * The two directories tela owns on local storage, and the one rule for creating
 * them.
 *
 * Shared rather than repeated: the app-private tier is written by [TierWriting],
 * listed by [PrivateTierListing] and deleted from by [TierDeleting], and three
 * spellings of `File(context.filesDir, "wallpapers")` is how one of them ends up
 * pointing somewhere else.
 *
 * ```
 * val directory = TelaDirectories.privateImages(context)
 * if (!TelaDirectories.ensure(directory)) return imageStoreFailure("unavailable")
 * ```
 */
internal object TelaDirectories {
    /** The app-private tier: visible to nothing but tela, gone on uninstall. */
    fun privateImages(context: Context): File = File(context.filesDir, "wallpapers")

    /** Throwaway copies made decodable for the viewer, under the cache dir. */
    fun previews(context: Context): File = File(context.cacheDir, "previews")

    /**
     * Every file in the app-private tier: its root, plus one directory down.
     *
     * **Shared by the listing and the delete, and that is the point.** A tag is
     * a folder in this tier, so both have to descend — and if only one of them
     * did, the mismatch would be invisible: [TierDeleting.deletePrivate] treats
     * "no matching file" as success, on the sound rule that a file already gone
     * counts as deleted. A shallow delete beside a deep listing would therefore
     * report every tagged image deleted and remove none of them, with no error
     * anywhere. One walk, one depth, one place to change it.
     *
     * **Exactly one level**, because that is exactly what tela writes: nothing
     * composes a deeper path than `wallpapers/<tag>/<file>`. A directory whose
     * name is not a valid tag is skipped whole, the same judgement
     * [ImageFileNaming.keyOf] makes about a file tela did not name — a user is
     * free to drop things in here, and guessing at them is worse than leaving
     * them alone.
     */
    fun privateFiles(context: Context): List<File> {
        val children = privateImages(context).listFiles() ?: return emptyList()
        val loose = children.filter { it.isFile }
        val tagged = children
            .filter { it.isDirectory && TagFolders.isValid(it.name) }
            .flatMap { folder -> folder.listFiles()?.filter { it.isFile } ?: emptyList() }
        return loose + tagged
    }

    /**
     * Whether [file] really sits inside the app-private tier, symlinks resolved.
     *
     * The confinement every caller holding a private location must pass before
     * it touches the file: those locations cross a method channel, and
     * `file:///data/data/cc.pym.tela/databases/tela` is a perfectly well-formed
     * one. Canonical, not textual, so a symlink cannot point out of the tier
     * after the string has been checked. The same guard shape
     * [StoredImageReading.releasePreview] applies to the preview cache.
     */
    fun holdsPrivateFile(context: Context, file: File): Boolean {
        return try {
            file.canonicalPath.startsWith(privateImages(context).canonicalPath + File.separator)
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Makes sure [directory] exists, tolerating another thread creating it first.
     *
     * The obvious `!exists() && !mkdirs()` is **not** thread-safe, and stopped
     * being merely theoretical when downloads moved onto a thread pool
     * (`Downloads.executor`): two concurrent stores both see the directory
     * missing, both call `mkdirs`, and the loser gets `false` for a directory
     * that now exists — so a perfectly good download reported `unavailable` and
     * wrote nothing. Found by `ConcurrentDownloadTest`.
     *
     * What matters is the state afterwards, not who created it.
     */
    fun ensure(directory: File): Boolean {
        directory.mkdirs()
        return directory.isDirectory
    }
}
