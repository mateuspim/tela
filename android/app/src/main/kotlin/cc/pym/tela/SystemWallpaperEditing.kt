package cc.pym.tela

import android.app.Activity
import android.app.WallpaperManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import java.io.File

/**
 * Opens Android's own crop-and-set editor on a wallpaper.
 *
 * This is the OEM's picker — on a Samsung, the same screen the gallery opens,
 * with reposition and the clock and widget preview. tela stops at the hand-off:
 * the editor owns the crop, the Home/Lock/Both choice and the apply itself, and
 * hands nothing back, so a success here means the editor opened and no more.
 * That is why this is not part of the applier, which reports what it did.
 *
 * The domain refuses to route an explicit wallpaper here (AdjustWallpaper), so
 * the bytes reaching this class are always non-explicit — the same rule, and
 * for the same reason, as WallpaperSharing: the editor is a separate app, and
 * keeps a wallpaper history tela does not control.
 *
 * Two calls on purpose, like WallpaperSharing: [downloadToCache] does the
 * network work and must run off the UI thread, while [openEditorOn] starts an
 * activity and must run on it.
 */
class SystemWallpaperEditing(private val activity: Activity) {
    private val cache = ImageHandoffCache(activity, ADJUST_DIRECTORY)

    /**
     * Downloads [imageUrl] under [fileName], returning the file or null when
     * the fetch fails. Run this off the UI thread.
     */
    fun downloadToCache(imageUrl: String, fileName: String): File? =
        cache.download(imageUrl, fileName)

    /**
     * Launches the system editor for [file]. Run this on the UI thread.
     *
     * Two ways in, tried in order: AOSP's direct crop-and-set, then the OEM
     * "Use image as…" chooser. resolveActivity is deliberately not used to spot
     * a missing editor — from API 30 a package-visibility filter can hide a
     * handler from our own query even when the device has one, so a null there
     * would refuse a picker that exists. The chooser sidesteps that entirely:
     * the system resolver enumerates handlers out of our process. Catching
     * ActivityNotFoundException is correct however the query is filtered.
     */
    fun openEditorOn(file: File): Map<String, Any> {
        val uri = cache.contentUri(file)
        val intent = cropAndSetIntent(uri) ?: attachDataChooser(uri)
        return try {
            activity.startActivity(intent)
            mapOf("success" to true)
        } catch (_: ActivityNotFoundException) {
            failure("noEditor")
        }
    }

    /**
     * AOSP's direct crop-and-set editor, or null when the platform refuses it.
     *
     * One UI has no such editor to give: getCropAndSetWallpaperIntent pins the
     * intent to the default launcher and then to a configured cropper package,
     * and Samsung ships neither as a handler, so it throws rather than returns.
     * Falling back to [attachDataChooser] reaches Samsung's own "Set as
     * wallpaper" screen — the crop / Home-Lock / widgets one Gallery opens.
     * Verified dead on an SM-X730 (One UI 7); kept for stock Android, where it
     * gives a cleaner one-tap cropper than the chooser.
     */
    private fun cropAndSetIntent(uri: Uri): Intent? = try {
        WallpaperManager.getInstance(activity)
            .getCropAndSetWallpaperIntent(uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    } catch (_: IllegalArgumentException) {
        null
    }

    /**
     * The OEM "Use image as…" hand-off, as a chooser.
     *
     * ACTION_ATTACH_DATA is what Gallery fires for "Set as wallpaper"; on a
     * Samsung it resolves to the crop / Home-Lock / widgets editor. A chooser,
     * not a bare launch, so a stale "always" default for ATTACH_DATA (Contacts,
     * a photo app) cannot swallow the image instead. The read grant rides the
     * inner intent, which the resolver forwards to whichever handler is picked.
     */
    private fun attachDataChooser(uri: Uri): Intent {
        val attach = Intent(Intent.ACTION_ATTACH_DATA)
            .setDataAndType(uri, "image/*")
            .putExtra("mimeType", "image/*")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return Intent.createChooser(attach, null)
    }

    private fun failure(code: String): Map<String, Any> =
        mapOf("success" to false, "errorCode" to code)

    private companion object {
        const val ADJUST_DIRECTORY = "adjusted"
    }
}
