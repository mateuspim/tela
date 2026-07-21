package cc.pym.tela

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The volume-by-kind rule, tested with plain fakes and no Android runtime.
 *
 * This is where "a download goes to the wrong disk" is caught: the accessors
 * are supplied here, so device and card cannot be transposed, and an unmounted
 * card cannot be mistaken for a usable one, without a device in the loop.
 */
class VolumeSelectionTest {
    private data class Vol(
        val name: String,
        val primary: Boolean = false,
        val removable: Boolean = false,
        val mounted: Boolean = true,
    )

    private val device = Vol("internal", primary = true)
    private val card = Vol("sd", removable = true)
    private val volumes = listOf(device, card)

    private fun forKind(kind: String, volumes: List<Vol> = this.volumes) =
        VolumeSelection.forKind(
            kind,
            volumes,
            { it.primary },
            { it.removable },
            { it.mounted },
        )

    @Test
    fun `device names the primary volume, never the card`() {
        assertEquals(device, forKind("device"))
    }

    @Test
    fun `sd card names the removable volume, never the device`() {
        assertEquals(card, forKind("sdCard"))
    }

    @Test
    fun `an unmounted card is not offered`() {
        val ejected = listOf(device, card.copy(mounted = false))

        assertNull(forKind("sdCard", ejected))
    }

    @Test
    fun `a card asked for with none present names nothing`() {
        assertNull(forKind("sdCard", listOf(device)))
    }

    @Test
    fun `an unknown kind names nothing`() {
        assertNull(forKind("cloud"))
    }
}
