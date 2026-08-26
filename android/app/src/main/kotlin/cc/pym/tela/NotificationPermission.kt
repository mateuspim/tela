package cc.pym.tela

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

/**
 * Whether tela may still post the notification its background work runs behind.
 *
 * Declaring `POST_NOTIFICATIONS` in the manifest is not enough on Android 13+:
 * it is a runtime permission, and an app that never asks simply has every
 * notification dropped. tela declared it and never asked, so the download
 * queue's and the offload's shade notice had never once been seen on the
 * owner's device — 588 posts, 588 blocked (2026-08-25).
 *
 * The cost is not only the missing text. That notification is the foreground
 * service's, so the move that was built to outlive the screen was running with
 * nothing on screen to say it existed and no way to stop it from the shade.
 *
 * ```
 * if (NotificationPermission.isMissing(context)) requestPermissions(...)
 * ```
 */
internal object NotificationPermission {
    /** The request code the activity hands back for this permission. */
    const val REQUEST = 403

    /** The permission itself, so no caller has to spell it. */
    val NAME: String = Manifest.permission.POST_NOTIFICATIONS

    /**
     * Whether the permission is needed and not yet held.
     *
     * False below Android 13, where notifications need no grant at all — asking
     * there would raise a dialog the platform has no answer for.
     */
    fun isMissing(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        return context.checkSelfPermission(NAME) != PackageManager.PERMISSION_GRANTED
    }
}
