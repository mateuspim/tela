package cc.pym.tela

import android.app.WallpaperManager
import android.content.Context
import android.net.Uri
import java.io.InputStream

/**
 * Writes an image onto one or both wallpaper surfaces.
 *
 * **Extracted so the activity and the rotation worker share one path.** The
 * sequential-write quirk below is an OEM workaround discovered on hardware; a
 * second copy of this logic in the worker would drift from it silently, and the
 * symptom — a scheduled rotation that only ever changes the home screen on a
 * Samsung — would look like a scheduling bug rather than a duplicated one.
 *
 * Reads from a stream rather than a path so a MediaStore `content:` URI and an
 * app-private `File` reach the same code.
 *
 * ```
 * WallpaperSetting.apply(context, "both") { file.inputStream() }
 * ```
 */
internal object WallpaperSetting {
    /** Restrictive OEMs need a gap between the two writes; see [applyBoth]. */
    private const val BETWEEN_TARGETS_DELAY_MS = 500L

    /**
     * Applies the image [open] yields to [target], which is `home|lock|both`.
     *
     * [open] is called once per surface rather than handed a single stream:
     * `setStream` consumes what it is given, so `both` needs two, and reusing
     * one silently sets the second surface from an exhausted stream.
     *
     * @throws IllegalArgumentException naming [target] when it is not one of
     *   the three surfaces.
     */
    fun apply(context: Context, target: String, open: () -> InputStream) {
        val wallpaper = WallpaperManager.getInstance(context)
        when (target) {
            "home" -> write(wallpaper, open, WallpaperManager.FLAG_SYSTEM)
            "lock" -> write(wallpaper, open, WallpaperManager.FLAG_LOCK)
            "both" -> applyBoth(wallpaper, open)
            else -> throw IllegalArgumentException("target must be home|lock|both, got \"$target\"")
        }
    }

    /** Applies [source] from the content resolver — a MediaStore or SAF URI. */
    fun applyUri(context: Context, target: String, source: Uri) {
        apply(context, target) {
            context.contentResolver.openInputStream(source)
                ?: throw IllegalStateException("the wallpaper source could not be opened")
        }
    }

    /**
     * Both surfaces, written one after the other.
     *
     * A combined flag often changes only the home screen on restrictive OEMs,
     * so these are two distinct writes with a pause between them.
     */
    private fun applyBoth(wallpaper: WallpaperManager, open: () -> InputStream) {
        write(wallpaper, open, WallpaperManager.FLAG_SYSTEM)
        Thread.sleep(BETWEEN_TARGETS_DELAY_MS)
        write(wallpaper, open, WallpaperManager.FLAG_LOCK)
    }

    private fun write(wallpaper: WallpaperManager, open: () -> InputStream, flag: Int) {
        open().use { stream -> wallpaper.setStream(stream, null, true, flag) }
    }
}
