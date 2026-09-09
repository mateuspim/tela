package cc.pym.tela

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class StreamDigestTest {
    @Test
    fun `copy digest matches the bytes read back from the destination`() {
        val source = ByteArray(DEFAULT_BUFFER_SIZE * 2 + 17) { it.toByte() }
        val destination = ByteArrayOutputStream()

        val copied = copyAndDigest(ByteArrayInputStream(source), destination)

        assertArrayEquals(source, destination.toByteArray())
        assertArrayEquals(copied, digestOf(ByteArrayInputStream(destination.toByteArray())))
    }

    @Test
    fun `a changed destination has a different digest`() {
        val source = byteArrayOf(1, 2, 3)
        val changed = byteArrayOf(1, 2, 4)
        assertFalse(
            digestOf(ByteArrayInputStream(source)).contentEquals(
                digestOf(ByteArrayInputStream(changed)),
            ),
        )
    }
}
