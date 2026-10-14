package cc.pym.tela

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImageCompletenessTest {
    private fun bytes(vararg values: Int): ByteArray = ByteArray(values.size) { values[it].toByte() }

    private val jpegHead = bytes(0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46, 0x49, 0x46, 0, 1)
    private val pngHead = bytes(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D)

    /** Regression: an unverified offload left 0-byte documents on the card (2026-10-07). */
    @Test
    fun `a zero-byte file is empty`() {
        assertEquals(ImageCompleteness.EMPTY, ImageCompleteness.judge(0, ByteArray(0), ByteArray(0)))
    }

    @Test
    fun `a jpeg ending on its marker is intact`() {
        assertEquals(ImageCompleteness.INTACT, ImageCompleteness.judge(100, jpegHead, bytes(1, 2, 0xFF, 0xD9)))
    }

    @Test
    fun `a jpeg with no end marker is truncated`() {
        assertEquals(ImageCompleteness.TRUNCATED, ImageCompleteness.judge(100, jpegHead, bytes(1, 2, 3, 4)))
    }

    /** Some cameras append data after the marker; that file is still whole. */
    @Test
    fun `a jpeg with data after its marker is intact`() {
        assertEquals(ImageCompleteness.INTACT, ImageCompleteness.judge(100, jpegHead, bytes(0xFF, 0xD9, 7, 7, 7)))
    }

    @Test
    fun `a png needs its IEND chunk`() {
        val iend = "IEND".toByteArray() + bytes(0xAE, 0x42, 0x60, 0x82)
        assertEquals(ImageCompleteness.INTACT, ImageCompleteness.judge(100, pngHead, iend))
        assertEquals(ImageCompleteness.TRUNCATED, ImageCompleteness.judge(100, pngHead, bytes(1, 2, 3)))
    }

    @Test
    fun `a webp shorter than its RIFF length is truncated`() {
        // RIFF length 92 + 8 header bytes = 100.
        val head = "RIFF".toByteArray() + bytes(92, 0, 0, 0) + "WEBP".toByteArray()
        assertEquals(ImageCompleteness.INTACT, ImageCompleteness.judge(100, head, ByteArray(0)))
        assertEquals(ImageCompleteness.TRUNCATED, ImageCompleteness.judge(60, head, ByteArray(0)))
    }

    /** A verdict leads to an overwrite or a delete, so "unknown" must pass. */
    @Test
    fun `an unknown format is never called broken`() {
        assertEquals(ImageCompleteness.INTACT, ImageCompleteness.judge(100, bytes(1, 2, 3), bytes(4, 5, 6)))
    }

    @Test
    fun `only a jpeg ending exactly on its marker skips the wide read`() {
        assertTrue(ImageCompleteness.endsCleanly(jpegHead, bytes(0xFF, 0xD9)))
        assertFalse(ImageCompleteness.endsCleanly(jpegHead, bytes(0xD9, 0x00)))
        assertFalse(ImageCompleteness.endsCleanly(pngHead, bytes(0xFF, 0xD9)))
    }
}
