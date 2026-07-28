package cc.pym.tela

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Covers the half of folder description that does not need a real volume.
 *
 * Robolectric does not usefully emulate `StorageManager` or SAF, so the volume
 * label, removability, free space and availability stay device-verified. What
 * *is* covered here is the part that would silently misreport a card: the tree
 * document id split, which is pure, and the refusal to describe anything that
 * is not a granted external-storage tree.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DownloadFolderDescribingTest {
    private lateinit var describing: DownloadFolderDescribing

    @Before
    fun setUp() {
        val context: Context = ApplicationProvider.getApplicationContext()
        describing = DownloadFolderDescribing(context)
    }

    // --- the tree document id split -----------------------------------------

    @Test
    fun `a card tree splits into its uuid and the path inside it`() {
        val location = TreeLocation.parse("1A2B-3C4D:Wallpapers/tela")

        assertEquals("1A2B-3C4D", location?.volumeId)
        assertEquals("Wallpapers/tela", location?.relativePath)
        assertFalse(location!!.isPrimary)
    }

    @Test
    fun `built-in storage is recognised as the primary volume`() {
        val location = TreeLocation.parse("primary:Pictures/sync")

        assertEquals("Pictures/sync", location?.relativePath)
        assertEquals(true, location?.isPrimary)
    }

    @Test
    fun `a volume root has an empty path, not a slash`() {
        // The path is concatenated for display; a stray separator would show
        // the user "SD card//tela".
        assertEquals("", TreeLocation.parse("1A2B-3C4D:")?.relativePath)
        assertEquals("", TreeLocation.parse("primary:/")?.relativePath)
    }

    @Test
    fun `a path keeps its inner separators and loses only the outer ones`() {
        assertEquals("a/b/c", TreeLocation.parse("primary:/a/b/c/")?.relativePath)
    }

    @Test
    fun `an id with no volume separator is not a tree`() {
        assertNull(TreeLocation.parse("Pictures/tela"))
    }

    @Test
    fun `the path shown is the tela child, not the folder the user pointed at`() {
        // The row would otherwise name a folder tela never writes into.
        assertEquals("Wallpapers/tela", TreeLocation.parse("1A2B-3C4D:Wallpapers")?.telaFolderPath)
        assertEquals("tela", TreeLocation.parse("primary:")?.telaFolderPath)
    }

    @Test
    fun `an id starting with the separator has no volume to name`() {
        // Guards the `<= 0` boundary: substring(0, 0) would otherwise hand back
        // an empty volume id that matches no volume and reads as a card.
        assertNull(TreeLocation.parse(":Pictures"))
    }

    // --- what may be described at all ---------------------------------------

    @Test
    fun `an ungranted tier succeeds with no folder rather than an error`() {
        // "Nothing chosen yet" is an ordinary state the row draws as "not set",
        // not a failure — and the card flag still has to come back so the row
        // can offer a card before anything is configured.
        val result = describing.describe(null)

        assertEquals(true, result["success"])
        assertFalse(result.containsKey("folder"))
        assertTrue(result["sdCardAvailable"] is Boolean)
    }

    @Test
    fun `a tree from another provider yields no folder`() {
        // Only the external-storage provider serves the volumes this tier
        // writes to; a downloads- or cloud-provider tree describes a folder tela
        // cannot actually write into, so it comes back with no folder at all.
        //
        // The document id here is deliberately a *well-formed* one
        // (`primary:Pictures`). An id that fails to parse would make this pass
        // with the authority check deleted — mutation caught exactly that, and
        // it is the same vacuous shape recorded in HANDOFF's F section.
        val result = describing.describe(
            "content://com.android.providers.downloads/tree/primary%3APictures",
        )

        assertEquals(true, result["success"])
        assertFalse(result.containsKey("folder"))
    }

    @Test
    fun `a malformed tree uri yields no folder rather than crashing`() {
        val result = describing.describe("not-a-uri")

        assertEquals(true, result["success"])
        assertFalse(result.containsKey("folder"))
    }

    // --- availability, the store gate's notConfigured-vs-ejected question ----

    @Test
    fun `a foreign-provider tree is unavailable, never writable`() {
        // The store gate calls this to decide folderUnavailable; a tree from a
        // provider that does not serve these volumes names nothing tela can
        // write into, so it is unavailable rather than crashing the gate.
        assertFalse(
            describing.isAvailable(
                "content://com.android.providers.downloads/tree/primary%3APictures",
            ),
        )
    }

    @Test
    fun `a well-formed tree with no held grant is unavailable`() {
        // Robolectric holds no persisted permissions, so a properly shaped
        // external-storage tree is still unwritable here — proving the grant
        // check, not just the authority guard, gates availability. The device
        // suite covers the granted-and-mounted true case.
        assertFalse(
            describing.isAvailable(
                "content://com.android.externalstorage.documents/tree/primary%3APictures%2Ftela",
            ),
        )
    }

    @Test
    fun `a malformed availability tree does not crash the gate`() {
        assertFalse(describing.isAvailable("not-a-uri"))
    }
}
