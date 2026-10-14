package cc.pym.tela

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StreamDigestTest {
    @Test
    fun `copy digest matches the bytes read back from the destination`() {
        val source = ByteArray(DEFAULT_BUFFER_SIZE * 2 + 17) { it.toByte() }
        val destination = ByteArrayOutputStream()

        val copied = copyAndDigest(ByteArrayInputStream(source), destination)

        assertArrayEquals(source, destination.toByteArray())
        assertTrue(copied.sameAs(digestOf(ByteArrayInputStream(destination.toByteArray()))))
    }

    @Test
    fun `the digest counts the bytes it read`() {
        val source = ByteArray(DEFAULT_BUFFER_SIZE + 5)

        assertEquals(source.size.toLong(), digestOf(ByteArrayInputStream(source)).length)
    }

    /**
     * The shape a skipped truncate leaves: the new bytes, then the old file's
     * tail. It must never pass for the copy it starts with.
     */
    @Test
    fun `a destination with a leftover tail is not the same copy`() {
        val source = byteArrayOf(1, 2, 3)
        val withTail = byteArrayOf(1, 2, 3, 9, 9)

        assertFalse(
            digestOf(ByteArrayInputStream(source)).sameAs(digestOf(ByteArrayInputStream(withTail))),
        )
    }

    @Test
    fun `nothing read back is never the same copy`() {
        assertFalse(digestOf(ByteArrayInputStream(byteArrayOf(1))).sameAs(null))
    }

    @Test
    fun `a changed destination has a different digest`() {
        val source = byteArrayOf(1, 2, 3)
        val changed = byteArrayOf(1, 2, 4)
        assertFalse(
            digestOf(ByteArrayInputStream(source)).sameAs(digestOf(ByteArrayInputStream(changed))),
        )
    }
}
