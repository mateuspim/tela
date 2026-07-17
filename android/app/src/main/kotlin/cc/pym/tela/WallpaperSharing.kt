package cc.pym.tela

import android.app.Activity
import android.content.Intent
import java.io.File

/**
 * Launches Android's share sheet for a wallpaper — a link or the image file.
 *
 * A link is plain text and sends nothing tela is holding. An image is fetched
 * into a private cache folder and handed to the receiver through a FileProvider
 * content URI with a one-shot read grant, so no storage permission is involved.
 * The domain refuses to route an explicit wallpaper here (ShareWallpaper.image),
 * so the bytes that reach this class are always non-explicit.
 *
 * The image path is two calls on purpose: [downloadToShareCache] does the
 * network work and must run off the UI thread, while [shareImageFile] launches
 * the chooser and must run on it.
 */
class WallpaperSharing(private val activity: Activity) {
    private val cache = ImageHandoffCache(activity, SHARE_DIRECTORY)

    /** Fires an ACTION_SEND chooser for [page]. Returns tela's result map. */
    fun shareLink(page: String): Map<String, Any> {
        val intent = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, page)
        return launch(intent)
    }

    /**
     * Downloads [imageUrl] into cache under [fileName], returning the file or
     * null when the fetch fails. Run this off the UI thread.
     *
     * The shared-cache folder is emptied first, so a past share cannot pile up
     * in cache — only the wallpaper being shared right now is ever exposed.
     */
    fun downloadToShareCache(imageUrl: String, fileName: String): File? =
        cache.download(imageUrl, fileName)

    /** Fires an ACTION_SEND chooser for [file]. Run this on the UI thread. */
    fun shareImageFile(file: File): Map<String, Any> {
        val uri = cache.contentUri(file)
        val intent = Intent(Intent.ACTION_SEND)
            .setType(activity.contentResolver.getType(uri) ?: "image/*")
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return launch(intent)
    }

    private fun launch(intent: Intent): Map<String, Any> {
        val chooser = Intent.createChooser(intent, null)
        if (chooser.resolveActivity(activity.packageManager) == null) {
            return failure("noTarget")
        }
        activity.startActivity(chooser)
        return mapOf("success" to true)
    }

    private fun failure(code: String): Map<String, Any> =
        mapOf("success" to false, "errorCode" to code)

    private companion object {
        const val SHARE_DIRECTORY = "shared"
    }
}
