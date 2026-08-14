package cc.pym.tela

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.PersistableBundle
import java.io.File

/**
 * Puts a wallpaper's image file on the system clipboard, for pasting into
 * another app without a chooser in between.
 *
 * Same hand-off as [WallpaperSharing]'s image path — fetch into a private cache
 * folder, expose it through a FileProvider content URI — but the clip outlives
 * the call, so the file has to stay readable after tela is done with it. That
 * is why the clipboard gets its own cache folder rather than sharing the share
 * sheet's: [ImageHandoffCache] empties the folder on the way in, so a share
 * taken right after a copy would delete the very file the clipboard points at
 * and the paste would come back empty.
 *
 * The clip's URI grant is the system's to hand out: putting a content URI on
 * the primary clip makes the framework grant read access to whoever pastes it,
 * so no permission of tela's is involved. It also means the clipboard is a
 * wider hand-off than a share — every app that reads the clipboard can take
 * these bytes — which is why the domain refuses to route an explicit wallpaper
 * here (ShareWallpaper.clipboard).
 *
 * Two calls on purpose, like the share path: [downloadToClipboardCache] does
 * network work and must run off the UI thread, while [copyToClipboard] touches
 * ClipboardManager, which needs a Looper and the foreground.
 */
class WallpaperClipboard(private val context: Context) {
    private val cache = ImageHandoffCache(context, CLIPBOARD_DIRECTORY)

    /**
     * Downloads [imageUrl] into cache under [fileName], returning the file or
     * null when the fetch fails. Run this off the UI thread.
     */
    fun downloadToClipboardCache(imageUrl: String, fileName: String): File? =
        cache.download(imageUrl, fileName)

    /**
     * Puts [file] on the clipboard under [fileName] as its label. Returns
     * tela's result map, carrying whether Android showed its own confirmation.
     * Run this on the UI thread.
     *
     * [sensitive] is set for an explicit wallpaper, which tela does copy (that
     * decision lives in `shareOptionsFor`). It is the one thing still under
     * tela's control once the bytes are on the clipboard: from Android 13 the
     * system draws a preview of what was copied, and this makes it a placeholder
     * rather than the picture — on a device someone else may be looking at.
     */
    fun copyToClipboard(
        file: File,
        fileName: String,
        sensitive: Boolean,
    ): Map<String, Any> {
        val clipboard = context.getSystemService(ClipboardManager::class.java)
            ?: return mapOf("success" to false, "errorCode" to "noTarget")
        val uri = cache.contentUri(file)
        val clip = ClipData.newUri(context.contentResolver, fileName, uri)
        if (sensitive) clip.description.extras = sensitiveExtras()
        clipboard.setPrimaryClip(clip)
        return mapOf("success" to true, "systemNotice" to showsOwnClipboardNotice())
    }

    /**
     * The clip metadata that hides a preview. Named by [ClipDescription] from
     * API 33; the constant is inlined below that, where nothing reads it and an
     * unknown extra is simply carried along.
     */
    private fun sensitiveExtras(): PersistableBundle = PersistableBundle().apply {
        putBoolean(EXTRA_IS_SENSITIVE, true)
    }

    /**
     * Whether Android confirms a copy itself — its clipboard preview arrived in
     * 13 (API 33), and a toast of tela's on top of it says the same thing twice.
     */
    private fun showsOwnClipboardNotice(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

    private companion object {
        const val CLIPBOARD_DIRECTORY = "clipboard"

        /** `ClipDescription.EXTRA_IS_SENSITIVE`, spelled out for minSdk 29. */
        const val EXTRA_IS_SENSITIVE = "android.content.extra.IS_SENSITIVE"
    }
}
