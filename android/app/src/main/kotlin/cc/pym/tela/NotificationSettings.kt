package cc.pym.tela

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.provider.Settings

/**
 * Reading and reaching tela's own notification switch.
 *
 * **An app cannot turn its own notifications on.** The platform offers a grant
 * dialog once (see [NotificationPermission]) and after that the only way back
 * is the system screen, and there is no API at all for turning them *off* —
 * which is why the settings row here opens Android's page rather than flipping
 * a switch of its own. A toggle tela drew itself would be a lie in both
 * directions: unable to grant, and unable to revoke.
 *
 * ```
 * NotificationSettings(context).areEnabled()  // false while the shade is muted
 * ```
 */
internal class NotificationSettings(private val context: Context) {
    /** Whether anything tela posts would actually be shown. */
    fun areEnabled(): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java)
        return manager?.areNotificationsEnabled() == true
    }

    /**
     * Opens Android's notification page for tela, answering whether it opened.
     *
     * `NEW_TASK` because this may be launched from an application context, and
     * a failure is reported rather than thrown: a device with the settings
     * activity missing must cost the row its tap, not the app its process.
     */
    fun open(): Boolean {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }
}
