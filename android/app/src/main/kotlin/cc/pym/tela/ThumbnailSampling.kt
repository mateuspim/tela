package cc.pym.tela

/**
 * How much to shrink a bitmap decode by, given its real size and a target.
 *
 * `BitmapFactory.Options.inSampleSize` only accepts powers of two, so this
 * doubles until one more doubling would put the *larger* side under
 * [maxDimensionPx] — the same convention `WallpaperTile` uses for width, just
 * measured against whichever side is bigger so a landscape and a portrait
 * source both land near the same target size. Pure arithmetic, kept separate
 * from [StoredImageReading] so it can be checked without a decoded bitmap.
 */
internal fun sampleSizeFor(width: Int, height: Int, maxDimensionPx: Int): Int {
    var sampleSize = 1
    val longestSide = maxOf(width, height)
    while (longestSide / (sampleSize * 2) >= maxDimensionPx) {
        sampleSize *= 2
    }
    return sampleSize
}
