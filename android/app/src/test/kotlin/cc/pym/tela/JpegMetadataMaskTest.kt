package cc.pym.tela

import java.io.ByteArrayInputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The copy check through [digestOf], over a hand-built JPEG: SOI, an APP1
 * standing in for a GPS block, a DQT table, then SOS and scan bytes.
 */
class JpegMetadataMaskTest {
    private fun jpeg(): ByteArray = bytes(
        0xFF, 0xD8,
        0xFF, 0xE1, 0x00, 0x08, 0x47, 0x50, 0x53, 0x31, 0x32, 0x33, // APP1, body 6..11
        0xFF, 0xDB, 0x00, 0x06, 0x01, 0x02, 0x03, 0x04, // DQT, body 16..19
        0xFF, 0xDA, 0x00, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0xFF, 0xD9,
    )

    private fun bytes(vararg values: Int): ByteArray = ByteArray(values.size) { values[it].toByte() }

    private fun changedAt(offset: Int): ByteArray = jpeg().also { it[offset] = 0 }

    private fun sameCopy(a: ByteArray, b: ByteArray): Boolean =
        digestOf(ByteArrayInputStream(a)).sameAs(digestOf(ByteArrayInputStream(b)))

    /** Regression: Android blanks GPS on readback, keeping the length (2026-10-07). */
    @Test
    fun `a rewritten metadata body still counts as the same copy`() {
        assertTrue(sameCopy(jpeg(), changedAt(8)))
    }

    @Test
    fun `a changed scan byte is a different copy`() {
        assertFalse(sameCopy(jpeg(), changedAt(26)))
    }

    @Test
    fun `a changed table is a different copy`() {
        assertFalse(sameCopy(jpeg(), changedAt(17)))
    }

    @Test
    fun `a changed segment length is a different copy`() {
        assertFalse(sameCopy(jpeg(), changedAt(5)))
    }

    /** No SOI, no masking: a PNG keeps the strict check. */
    @Test
    fun `a non-jpeg is compared whole`() {
        val png = ByteArray(32) { it.toByte() }

        assertFalse(sameCopy(png, png.copyOf().also { it[10] = 99 }))
    }

    /** The mask must not depend on where the read buffer happens to split. */
    @Test
    fun `byte-at-a-time feeding masks the same bytes`() {
        val source = jpeg()
        assertEquals(compared(source, source.size), compared(source, 1))
    }

    private fun compared(source: ByteArray, chunk: Int): List<Byte> {
        val kept = mutableListOf<Byte>()
        val mask = JpegMetadataMask()
        for (start in source.indices step chunk) {
            val piece = source.copyOfRange(start, minOf(start + chunk, source.size))
            mask.feed(piece, piece.size) { b, from, n -> kept += b.copyOfRange(from, from + n).toList() }
        }
        return kept
    }
}
