package cc.pym.tela

import java.io.ByteArrayInputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ByteDifferenceTest {
    private fun between(a: ByteArray, b: ByteArray): ByteDifference? =
        ByteDifference.between(ByteArrayInputStream(a), ByteArrayInputStream(b))

    @Test
    fun `identical streams have no difference`() {
        assertNull(between(byteArrayOf(1, 2, 3), byteArrayOf(1, 2, 3)))
    }

    /** The shape a metadata rewrite leaves: a short run near the start. */
    @Test
    fun `a run of changed bytes reports its bounds and size`() {
        val difference = between(byteArrayOf(1, 2, 3, 4, 5, 6), byteArrayOf(1, 0, 0, 4, 0, 6))!!

        assertEquals(1L, difference.firstAt)
        assertEquals(4L, difference.lastAt)
        assertEquals(3L, difference.count)
    }

    @Test
    fun `only the common length is compared`() {
        assertNull(between(byteArrayOf(1, 2), byteArrayOf(1, 2, 3)))
    }
}
