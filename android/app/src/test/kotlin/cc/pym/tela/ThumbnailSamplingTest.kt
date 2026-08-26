package cc.pym.tela

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pure arithmetic, deliberately kept apart from a decoded bitmap so it can be
 * checked without Robolectric — see [StoredImageReading.materialiseThumbnail].
 */
class ThumbnailSamplingTest {
    @Test
    fun `needs no shrinking when the source already fits`() {
        assertEquals(1, sampleSizeFor(width = 180, height = 320, maxDimensionPx = 200))
        assertEquals(1, sampleSizeFor(width = 200, height = 200, maxDimensionPx = 200))
    }

    @Test
    fun `halves until one more halving would undershoot the target`() {
        // 3840 / 2 = 1920, / 4 = 960, / 8 = 480 (still >= 200), / 16 = 240
        // (still >= 200) -- keep going until the next halving would drop
        // below 200: 3840 / 32 = 120 < 200, so 16 is the last one kept.
        assertEquals(16, sampleSizeFor(width = 3840, height = 2160, maxDimensionPx = 200))
    }

    @Test
    fun `measures against the longer side, whichever one it is`() {
        val portrait = sampleSizeFor(width = 1080, height = 2400, maxDimensionPx = 200)
        val landscape = sampleSizeFor(width = 2400, height = 1080, maxDimensionPx = 200)

        assertEquals(portrait, landscape)
    }

    @Test
    fun `is always a power of two, as BitmapFactory requires`() {
        for (dimension in 1..5000 step 137) {
            val sampleSize = sampleSizeFor(width = dimension, height = dimension, maxDimensionPx = 200)
            assertEquals(0, sampleSize and (sampleSize - 1))
        }
    }
}
