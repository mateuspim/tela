package cc.pym.tela

import android.app.WallpaperManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Rect
import android.os.Build
import java.io.File

/**
 * Applies a user-framed crop of a cached image to an Android wallpaper surface.
 *
 * tela's own cropper, the in-app counterpart to [SystemWallpaperEditing]: it
 * decodes only the chosen sub-rect and sets it here, in tela's process, so the
 * pixels never reach another app. That is why — unlike the OEM hand-off — this
 * path serves explicit wallpapers too.
 *
 * Deterministic where the platform is not: [WallpaperManager.setBitmap]'s
 * visibleCropHint is only a *hint* an OEM may reinterpret, so we crop the bitmap
 * ourselves with [BitmapRegionDecoder] and pass a null hint. Decoding just the
 * region — never the whole image — is also what keeps a 6K source off the heap.
 */
class WallpaperCropApplying(private val context: Context) {
    /**
     * Crops [file] to [region] and applies it to [target] (home|lock|both).
     *
     * Throws on any failure; the caller maps that to an `applyFailed` code.
     */
    fun apply(file: File, region: Rect, target: String) {
        val bitmap = decodeRegion(file, region)
        try {
            applyBitmap(bitmap, target)
        } finally {
            bitmap.recycle()
        }
    }

    /**
     * Decodes only [region] of [file], downsampled to stay off the heap.
     *
     * The requested rect is clamped to the decoder's real bounds first: the crop
     * maths runs on Wallhaven's reported resolution, and a mismatch of a pixel or
     * two would otherwise make decodeRegion throw.
     */
    private fun decodeRegion(file: File, region: Rect): Bitmap {
        val decoder = newRegionDecoder(file)
            ?: throw IllegalStateException("no region decoder for the cached image")
        try {
            val bounded = Rect(
                region.left.coerceIn(0, decoder.width),
                region.top.coerceIn(0, decoder.height),
                region.right.coerceIn(0, decoder.width),
                region.bottom.coerceIn(0, decoder.height),
            )
            val options = BitmapFactory.Options().apply {
                inSampleSize = sampleSizeFor(bounded)
            }
            return decoder.decodeRegion(bounded, options)
                ?: throw IllegalStateException("region decode returned null")
        } finally {
            decoder.recycle()
        }
    }

    private fun newRegionDecoder(file: File): BitmapRegionDecoder? {
        return file.inputStream().use { stream ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                BitmapRegionDecoder.newInstance(stream)
            } else {
                @Suppress("DEPRECATION")
                BitmapRegionDecoder.newInstance(stream, false)
            }
        }
    }

    /**
     * The power-of-two subsample that brings [region] under [MAX_DECODED_DIMENSION].
     *
     * A wallpaper never needs more than a few thousand pixels a side, while a
     * Wallhaven original can be 6K+ — decoding one at full size is the §15 OOM.
     */
    private fun sampleSizeFor(region: Rect): Int {
        val longestEdge = maxOf(region.width(), region.height())
        var sample = 1
        while (longestEdge / sample > MAX_DECODED_DIMENSION) sample *= 2
        return sample
    }

    private fun applyBitmap(bitmap: Bitmap, target: String) {
        val wallpaper = WallpaperManager.getInstance(context)
        when (target) {
            "home" -> wallpaper.setBitmap(bitmap, null, true, WallpaperManager.FLAG_SYSTEM)
            "lock" -> wallpaper.setBitmap(bitmap, null, true, WallpaperManager.FLAG_LOCK)
            "both" -> applyBoth(wallpaper, bitmap)
            else -> throw IllegalArgumentException("target must be home|lock|both, got \"$target\"")
        }
    }

    private fun applyBoth(wallpaper: WallpaperManager, bitmap: Bitmap) {
        wallpaper.setBitmap(bitmap, null, true, WallpaperManager.FLAG_SYSTEM)
        // Restrictive OEMs need distinct writes; a combined flag often changes
        // only home. Same reason as MainActivity.setBothWallpapers.
        Thread.sleep(BETWEEN_TARGETS_DELAY_MS)
        wallpaper.setBitmap(bitmap, null, true, WallpaperManager.FLAG_LOCK)
    }

    private companion object {
        const val MAX_DECODED_DIMENSION = 4096
        const val BETWEEN_TARGETS_DELAY_MS = 500L
    }
}
