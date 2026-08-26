package cc.pym.tela

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Whether tela may post at all — the gate its whole background story sits on.
 *
 * Declared in the manifest and never requested, which on Android 13+ means
 * every notification is dropped without a word. The offload was built to run
 * behind one (2026-08-25).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class NotificationPermissionTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun `is missing until it has been granted`() {
        shadowOf(context.applicationContext as android.app.Application)
            .denyPermissions(NotificationPermission.NAME)

        assertTrue(NotificationPermission.isMissing(context))
    }

    @Test
    fun `is not missing once granted`() {
        shadowOf(context.applicationContext as android.app.Application)
            .grantPermissions(NotificationPermission.NAME)

        assertFalse(NotificationPermission.isMissing(context))
    }

    /**
     * Nothing to ask for below Android 13 — raising the dialog there would ask
     * the platform a question it has no answer for.
     */
    @Test
    @Config(sdk = [31])
    fun `is never missing before Android 13`() {
        shadowOf(context.applicationContext as android.app.Application)
            .denyPermissions(NotificationPermission.NAME)

        assertFalse(NotificationPermission.isMissing(context))
    }
}
