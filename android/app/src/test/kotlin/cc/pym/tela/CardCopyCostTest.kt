package cc.pym.tela

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import androidx.test.core.app.ApplicationProvider
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowContentResolver

/**
 * What copying onto a card costs, measured in provider queries.
 *
 * Moving a library to the SD card "just hangs" (owner, 2026-11-04) because each
 * file listed whole folders several times: N files into a library of M was
 * N×M rows over a slow binder. These tests pin the cost to a constant per file
 * — against [FakeDocumentsProvider], which counts probes and listings — and
 * pin the behaviour that lookup must keep: case-insensitive matching, no
 * `(1)` duplicates, one wallpaper in one tag folder.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CardCopyCostTest {
    private val authority = "com.android.externalstorage.documents"
    private val rootId = "1234-5678:Offload"
    private lateinit var context: Context
    private lateinit var provider: FakeDocumentsProvider
    private lateinit var source: File
    private val tree: Uri =
        Uri.parse("content://$authority/tree/" + Uri.encode(rootId))

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        provider = FakeDocumentsProvider(context.cacheDir)
        provider.attachInfo(context, android.content.pm.ProviderInfo().apply {
            this.authority = this@CardCopyCostTest.authority
            exported = true
        })
        ShadowContentResolver.registerProviderInternal(authority, provider)
        provider.folder(rootId)
        source = File(context.cacheDir, "source.jpg").apply { writeText("pixels") }
        SafFolderMemo.clear()
    }

    @After
    fun tearDown() = SafFolderMemo.clear()

    private fun document(id: String): Uri = DocumentsContract.buildDocumentUriUsingTree(tree, id)

    private fun copy(id: String, tag: String? = null): Map<String, Any> {
        val result = ImageStorage(context).copy(
            ImageCopyRequest("wallhaven", id, Uri.fromFile(source).toString(), "sfw",
                "filesOutsideGallery", tag),
            OutsideGalleryTarget(tree.toString()),
        )
        val why = org.robolectric.shadows.ShadowLog.getLogs().filter { it.tag == "tela" }
            .joinToString { it.msg }
        assertEquals("$result $why", true, result["success"])
        return result
    }

    @Test
    fun `finding a child costs one probe and no listing`() {
        provider.file("$rootId/a.jpg")
        val found = SafDocuments.findChild(context, document(rootId), "a.jpg")
        assertNotNull(found)
        assertEquals(1, provider.probes)
        assertEquals(0, provider.listings)
    }

    @Test
    fun `a missing child is a null without a listing`() {
        assertNull(SafDocuments.findChild(context, document(rootId), "nope.jpg"))
        assertEquals(0, provider.listings)
    }

    @Test
    fun `the lookup stays case-insensitive like the card`() {
        provider.folder("$rootId/Alcololi")
        val found = SafDocuments.findChild(context, document(rootId), "alcololi")
        assertNotNull(found)
        assertEquals(listOf("Alcololi"), provider.namesUnder(rootId))
    }

    @Test
    fun `a volume root's children are addressed without a doubled slash`() {
        provider.folder("1234-5678:")
        provider.file("1234-5678:x.jpg")
        val root = document("1234-5678:")
        assertNotNull(SafDocuments.findChild(context, root, "x.jpg"))
    }

    /**
     * The copy lands at a new location, so without carrying the thumbnail
     * every moved tile was decoded again from the card (owner, 2026-11-04).
     */
    @Test
    fun `a copy carries the source's thumbnail to its new location`() {
        val directory = TelaDirectories.thumbnails(context).apply { mkdirs() }
        File(directory, StoredThumbnails.cacheName(Uri.fromFile(source), 400))
            .writeText("tile")

        val copied = Uri.parse(copy("aaa111")["location"] as String)

        val carried = File(directory, StoredThumbnails.cacheName(copied, 400))
        assertEquals("tile", carried.readText())
    }

    @Test
    fun `copying a file does not duplicate it when it is copied again`() {
        assertTrue(copy("aaa111")["success"] == true)
        assertTrue(copy("aaa111")["success"] == true)
        assertEquals(
            listOf(".nomedia", "wallhaven-aaa111.jpg"),
            provider.namesUnder("$rootId/tela").sorted(),
        )
    }

    @Test
    fun `copying under a new tag removes the other tag's copy`() {
        copy("aaa111", tag = "anime")
        copy("aaa111", tag = "minimal")
        assertFalse("wallhaven-aaa111.jpg" in provider.namesUnder("$rootId/tela/anime"))
        assertTrue("wallhaven-aaa111.jpg" in provider.namesUnder("$rootId/tela/minimal"))
    }

    @Test
    fun `copying untagged sweeps tag folders and keeps the new copy at the root`() {
        copy("aaa111", tag = "anime")
        copy("aaa111")
        assertEquals(null, provider.textOf("$rootId/tela/anime/wallhaven-aaa111.jpg"))
        assertEquals("pixels", provider.textOf("$rootId/tela/wallhaven-aaa111.jpg"))
    }

    @Test
    fun `listings per copied file do not grow with the library`() {
        provider.folder("$rootId/tela")
        provider.folder("$rootId/tela/anime")
        repeat(60) { provider.file("$rootId/tela/anime/wallhaven-old$it.jpg") }
        repeat(60) { provider.file("$rootId/tela/wallhaven-loose$it.jpg") }
        copy("warmup", tag = "anime")
        provider.resetCounts()
        repeat(10) { copy("new$it", tag = "anime") }
        // The tag folder list is remembered; nothing lists a folder per file.
        assertEquals(0, provider.listings)
        assertTrue("probes ${provider.probes}", provider.probes <= 10 * 12)
    }
}
