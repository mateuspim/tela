package cc.pym.tela

import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Which root inside a granted tree an image lands in — the vault rule, from the
 * outside.
 *
 * The SAF write itself needs a real DocumentsProvider and stays device-only, so
 * what is reachable here is the decision *around* it: that the rule is applied
 * by purity rather than by a caller, and that neither half of it can be reached
 * with a tree that was already refused.
 *
 * The half that is genuinely pinned mechanically is the placement — every route
 * into this tier goes through one `write`, so a test that reaches the tier at
 * all reaches the routing.
 *
 * See [ImageStorageTestCase] for what this suite can and cannot reach.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class VaultRoutingTest : ImageStorageTestCase() {
    private fun tree(documentId: String): String =
        "content://com.android.externalstorage.documents/tree/" + Uri.encode(documentId)

    private fun copyInto(
        purity: String,
        target: OutsideGalleryTarget,
        tag: String? = null,
    ): Map<String, Any> {
        val origin = writePrivateImage("wallhaven-abc123.jpg")
        return storage.copy(
            ImageCopyRequest(
                source = "wallhaven",
                id = "abc123",
                from = Uri.fromFile(origin).toString(),
                purity = purity,
                tier = "filesOutsideGallery",
                tag = tag,
            ),
            target,
        )
    }

    /**
     * The gallery-overlap guard runs before the vault is chosen, so an explicit
     * image cannot reach a hidden folder inside the gallery's own directory
     * either — the `.nomedia` disaster of 2026-07-28 by another door.
     */
    @Test
    fun `an explicit image is refused a tree that overlaps the gallery`() {
        val result = copyInto(
            "nsfw",
            OutsideGalleryTarget(tree("primary:Pictures")),
        )

        assertEquals("folderUnavailable", errorCodeOf(result))
    }

    @Test
    fun `a safe image is refused the same tree`() {
        val result = copyInto("sfw", OutsideGalleryTarget(tree("primary:Pictures")))

        assertEquals("folderUnavailable", errorCodeOf(result))
    }

    /**
     * A vault label that could not be a directory fails the write rather than
     * being repaired: an explicit image landing in a folder nobody chose is
     * worse than one that did not land.
     */
    @Test
    fun `an explicit image with an unusable vault label does not land`() {
        val result = copyInto(
            "nsfw",
            OutsideGalleryTarget(tree("primary:Wallpapers"), "../secrets"),
        )

        assertEquals(false, result["success"])
    }

    /**
     * `sketchy` follows the safe destination everywhere else in the app, so it
     * must not be vaulted here — a folder that disagreed with the configured
     * setting would be its own surprise.
     */
    @Test
    fun `sketchy is not treated as explicit by the vault rule`() {
        assertTrue(OutsideGalleryTarget(null).vaultDirectory == ".tela")
        // The gate above the routing accepts sketchy into every tier the safe
        // bucket may use, which is what makes the visible folder its home.
        val result = copyInto("sketchy", OutsideGalleryTarget(null))

        // No tree configured, so it stops at the same place a safe image does —
        // never at the "restricted" the explicit-into-gallery rule answers.
        assertEquals("notConfigured", errorCodeOf(result))
    }

    @Test
    fun `an explicit image without a tree reports the same missing folder`() {
        val result = copyInto("nsfw", OutsideGalleryTarget(null))

        assertEquals("notConfigured", errorCodeOf(result))
    }

    /**
     * The listing must not create what it reads. A settings screen that
     * conjured `.tela` into every granted tree just by being opened would leave
     * empty hidden folders behind on cards nothing was ever stored on.
     */
    @Test
    fun `listing a tree with no vault answers nothing and creates nothing`() {
        val listed = SafVaultListing(context).list(
            OutsideGalleryTarget(tree("primary:Wallpapers")),
        )

        assertTrue(listed.isEmpty())
    }

    @Test
    fun `listing with no tree at all is an empty answer, not a failure`() {
        assertTrue(SafVaultListing(context).list(OutsideGalleryTarget(null)).isEmpty())
    }

    /**
     * The private library is one screen over two homes, so its rows have to say
     * which one they came from: a delete routes by tier, and a document sent
     * down the app-private path is a file that delete cannot find.
     */
    @Test
    fun `app-private rows name their own tier`() {
        writePrivateImage("wallhaven-abc123.jpg")

        val images = imagesFrom(storage.listPrivate(noVault))

        assertEquals("appPrivate", images.single()["tier"])
    }

    /**
     * A tree that holds nothing must not disturb the tier that does — the
     * private library still has its own files to show.
     */
    @Test
    fun `an unreadable vault costs the listing nothing`() {
        writePrivateImage("wallhaven-abc123.jpg")

        val images = imagesFrom(
            storage.listPrivate(OutsideGalleryTarget(tree("primary:Wallpapers"))),
        )

        assertEquals(1, images.size)
    }
}
