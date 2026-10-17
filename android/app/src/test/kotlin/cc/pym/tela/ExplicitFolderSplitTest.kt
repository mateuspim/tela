package cc.pym.tela

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Safe and explicit downloads each with their own folder (owner, 2026-10-16).
 *
 * The rules worth pinning are the ones a device pass would only notice after
 * images had already gone somewhere wrong: which tree a purity writes into, that
 * a user who never chose a second folder keeps the one-folder layout, and that
 * moving the safe folder never drags explicit images along with it.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ExplicitFolderSplitTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences("tela.storage", Context.MODE_PRIVATE).edit().clear().commit()
    }

    // --- routing by purity ---------------------------------------------------

    @Test
    fun `explicit images write into the explicit tree`() {
        val target = OutsideGalleryTarget("safe", explicitTree = "explicit")

        assertEquals("explicit", target.treeFor("nsfw"))
    }

    @Test
    fun `safe and sketchy images write into the safe tree`() {
        val target = OutsideGalleryTarget("safe", explicitTree = "explicit")

        assertEquals("safe", target.treeFor("sfw"))
        assertEquals("safe", target.treeFor("sketchy"))
    }

    @Test
    fun `with no explicit tree chosen both purities share one`() {
        val target = OutsideGalleryTarget("only")

        assertEquals("only", target.treeFor("nsfw"))
        assertEquals(listOf("only"), target.vaultTrees)
    }

    @Test
    fun `vaults are read from both trees, explicit first`() {
        val target = OutsideGalleryTarget("safe", explicitTree = "explicit")

        assertEquals(listOf("explicit", "safe"), target.vaultTrees)
    }

    // --- what is stored ------------------------------------------------------

    @Test
    fun `a first safe folder leaves explicit following it`() {
        StorageTargetStore.saveTree(context, "card", "sfw")

        assertEquals("card", StorageTargetStore.explicitTree(context))
    }

    @Test
    fun `moving the safe folder keeps explicit where it was`() {
        StorageTargetStore.saveTree(context, "card", "sfw")
        StorageTargetStore.saveTree(context, "device", "sfw")

        assertEquals("device", StorageTargetStore.tree(context))
        assertEquals("card", StorageTargetStore.explicitTree(context))
    }

    @Test
    fun `choosing an explicit folder leaves the safe one alone`() {
        StorageTargetStore.saveTree(context, "device", "sfw")
        StorageTargetStore.saveTree(context, "card", "nsfw")

        assertEquals("device", StorageTargetStore.tree(context))
        assertEquals("card", StorageTargetStore.explicitTree(context))
    }

    @Test
    fun `an explicit folder chosen first leaves the safe one unset`() {
        StorageTargetStore.saveTree(context, "card", "nsfw")

        assertNull(StorageTargetStore.tree(context))
        assertEquals("card", StorageTargetStore.target(context).treeFor("nsfw"))
    }

    // --- what Settings is told -----------------------------------------------

    @Test
    fun `an ungranted tier describes neither folder`() {
        val result = DownloadFolderDescribing(context).describe(OutsideGalleryTarget(null))

        assertEquals(true, result["success"])
        assertFalse(result.containsKey("folder"))
        assertFalse(result.containsKey("explicitFolder"))
        assertEquals(VaultFolders.DEFAULT_LABEL, result["vaultLabel"])
    }
}
