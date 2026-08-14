package cc.pym.tela

import android.content.ClipboardManager
import android.content.Context
import androidx.core.content.FileProvider
import androidx.test.core.app.ApplicationProvider
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * What a clipboard copy leaves behind, and who tells the user about it.
 *
 * The two things worth defending here are the ones a device pass would not
 * notice going wrong. A clip carrying a *file* path rather than a content URI
 * pastes as text in some apps and as nothing in others, and the failure looks
 * like the receiving app's. And the copy's confirmation is split across two
 * layers — Android shows its own preview from 13, tela's toast covers every
 * release below it — so a wrong answer here means either silence or the same
 * news twice, on the releases nobody is testing on.
 *
 * The sensitive flag is here for a third reason: it is the only protection left
 * once explicit bytes are on the clipboard — tela copies those by the owner's
 * decision, see `shareOptionsFor` — and losing it is invisible until a preview
 * of the picture appears on someone's screen.
 *
 * SDK 35 for the same reason every Robolectric suite here pins it, and the
 * SDK-29 case is pinned per-method — see [ImageStorageTestCase].
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WallpaperClipboardTest {
    private lateinit var context: Context
    private lateinit var clipboard: WallpaperClipboard

    @Before
    fun openClipboard() {
        context = ApplicationProvider.getApplicationContext()
        clipboard = WallpaperClipboard(context)
        forgetCachedProviderRoots()
    }

    /**
     * Drops FileProvider's static root cache between tests.
     *
     * It resolves `<cache-path>` to an *absolute* path once per authority and
     * keeps it in a static map, while Robolectric hands each test its own
     * temporary data directory inside one sandbox. So the second test in a
     * class asks about a file under a path the cached roots have never heard
     * of, and `getUriForFile` throws "Failed to find configured root" — a
     * failure entirely of the harness's making, which on a device cannot
     * happen. Reflection because the cache is private and there is no reset.
     */
    private fun forgetCachedProviderRoots() {
        val cache = FileProvider::class.java.getDeclaredField("sCache")
        cache.isAccessible = true
        (cache.get(null) as MutableMap<*, *>).clear()
    }

    @Test
    fun `a copy puts a readable content URI on the clipboard`() {
        val result = clipboard.copyToClipboard(cachedImage(), IMAGE_NAME, sensitive = false)

        assertEquals(true, result["success"])
        val clip = systemClipboard().primaryClip
        assertEquals(1, clip?.itemCount)
        val uri = clip?.getItemAt(0)?.uri
        // A content URI, not a file path: the framework grants the pasting app
        // read access to the former and nothing at all to the latter.
        assertEquals("content", uri?.scheme)
        assertEquals("${context.packageName}.fileprovider", uri?.authority)
        assertTrue(uri.toString().endsWith(IMAGE_NAME))
    }

    @Test
    fun `the clip points into the clipboard's own cache folder`() {
        // The clip outlives the call, so the file behind it has to as well.
        // ImageHandoffCache empties its folder on the way in, so sharing the
        // share sheet's folder would leave the clipboard pointing at a file the
        // next share deleted — a paste that comes back empty minutes later,
        // with nothing logged. The segment also proves file_paths.xml declares
        // the folder: FileProvider throws for one it does not.
        clipboard.copyToClipboard(cachedImage(), IMAGE_NAME, sensitive = false)

        val uri = systemClipboard().primaryClip?.getItemAt(0)?.uri
        assertEquals(
            listOf("clipboard", IMAGE_NAME),
            uri?.pathSegments,
        )
    }

    @Test
    fun `an explicit copy is marked sensitive so no preview shows it`() {
        clipboard.copyToClipboard(cachedImage(), IMAGE_NAME, sensitive = true)

        val extras = systemClipboard().primaryClip?.description?.extras
        assertTrue(extras?.getBoolean("android.content.extra.IS_SENSITIVE") == true)
    }

    @Test
    fun `an ordinary copy carries no such mark`() {
        clipboard.copyToClipboard(cachedImage(), IMAGE_NAME, sensitive = false)

        val extras = systemClipboard().primaryClip?.description?.extras
        assertFalse(extras?.getBoolean("android.content.extra.IS_SENSITIVE") == true)
    }

    @Test
    fun `from Android 13 the system confirms the copy and tela stays quiet`() {
        val result = clipboard.copyToClipboard(cachedImage(), IMAGE_NAME, sensitive = false)

        assertEquals(true, result["systemNotice"])
    }

    @Test
    @Config(sdk = [29])
    fun `below Android 13 nothing is shown and tela owes the confirmation`() {
        val result = clipboard.copyToClipboard(cachedImage(), IMAGE_NAME, sensitive = false)

        assertEquals(false, result["systemNotice"])
    }

    /**
     * An image already staged in the clipboard cache, as [downloadToClipboardCache]
     * would leave it — the fetch itself needs a network and belongs to a device
     * pass, but everything after it does not.
     */
    private fun cachedImage(): File {
        val folder = File(context.cacheDir, "clipboard").apply { mkdirs() }
        folder.listFiles()?.forEach { it.delete() }
        return File(folder, IMAGE_NAME).apply { writeText("pixels") }
    }

    private fun systemClipboard(): ClipboardManager =
        context.getSystemService(ClipboardManager::class.java)

    private companion object {
        const val IMAGE_NAME = "wallhaven-e7jvjd.jpg"
    }
}
