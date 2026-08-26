package cc.pym.tela

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowLog

/**
 * What a failed tier write is allowed to say about itself.
 *
 * The rule under test is a privacy one, not a formatting one: this line is
 * written for NSFW writes as well, where the path *is* the disclosure.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class TierWriteLogTest {
    @Test
    fun `names the tier, the purity and the class that threw`() {
        TierWriteLog.failure("filesOutsideGallery", "nsfw", IllegalStateException("boom"))

        val fields = JSONObject(loggedPayload())
        assertEquals("filesOutsideGallery", fields.getString("tier"))
        assertEquals("nsfw", fields.getString("purity"))
        assertEquals("java.lang.IllegalStateException", fields.getString("error"))
    }

    @Test
    fun `names the cause as well, which is where SAF puts the real fault`() {
        val error = IllegalStateException("wrapper", java.io.FileNotFoundException("inner"))

        TierWriteLog.failure("filesOutsideGallery", "nsfw", error)

        assertEquals("java.io.FileNotFoundException", JSONObject(loggedPayload()).getString("cause"))
    }

    /**
     * The whole reason the message is dropped: SAF puts the document it failed
     * on into the exception text, and this line is written for explicit images
     * too. CLAUDE.md forbids logging an NSFW path anywhere.
     */
    @Test
    fun `never repeats the exception message, which carries the path`() {
        val path = "/storage/20FF-21F4/Pictures/Tela/.tela/private/wallhaven-abc123.jpg"

        TierWriteLog.failure("filesOutsideGallery", "nsfw", IllegalStateException(path))

        val line = ShadowLog.getLogs().single { it.tag == "tela" }.msg
        assertFalse(line.contains("wallhaven-abc123"))
        assertFalse(line.contains(".tela"))
        assertTrue(line.startsWith("tela.write "))
    }

    /**
     * The half that was missing first time round: most ways a write fails are
     * an ordinary `return imageStoreFailure(...)`, which never reaches a catch.
     */
    @Test
    fun `a refusal names its error code`() {
        TierWriteLog.refusal("filesOutsideGallery", "nsfw", "folderUnavailable")

        val fields = JSONObject(loggedPayload())
        assertEquals("folderUnavailable", fields.getString("code"))
        assertEquals("filesOutsideGallery", fields.getString("tier"))
    }

    @Test
    fun `a refusal with no code still says so rather than logging null`() {
        TierWriteLog.refusal("appPrivate", "sfw", null)

        assertEquals("unknown", JSONObject(loggedPayload()).getString("code"))
    }

    private fun loggedPayload(): String =
        ShadowLog.getLogs().single { it.tag == "tela" }.msg.removePrefix("tela.write ")
}
