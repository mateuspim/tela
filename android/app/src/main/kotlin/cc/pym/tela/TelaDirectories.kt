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
