package cc.pym.tela

import android.content.Intent
import android.content.IntentSender
import android.graphics.Rect
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * A FragmentActivity, not a plain FlutterActivity: local_auth's BiometricPrompt
 * needs a FragmentManager, and a plain FlutterActivity fails at prompt time
 * rather than at build time — so the app-lock would compile and then not work.
 *
 * **It is a screen, and only a screen.** The Flutter engine belongs to the
 * process ([TelaEngine]), and so do the channels a download needs
 * ([ImageStoreChannel], [DownloadQueueChannel]) — a queue that keeps draining
 * after tela is closed cannot answer through an activity that no longer exists.
 * What stays here is what genuinely needs a window: setting a wallpaper, the
 * share and crop hand-offs, FLAG_SECURE, and the two storage prompts the OS
 * only shows on top of an activity.
 */
class MainActivity : FlutterFragmentActivity(), StoragePrompts {
    private val wallpaperExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val shareExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var pendingFolderGrant: ((Uri?, Int) -> Unit)? = null
    private var pendingDeleteConfirmation: ((Boolean) -> Unit)? = null

    /**
     * Runs on tela's one cached engine, built the first time this is asked.
     *
     * The engine outliving the activity is what lets the download queue keep
     * draining through a swipe out of recents; see [TelaEngine] for why it is
     * created here rather than pre-warmed in `Application.onCreate`.
     */
    override fun getCachedEngineId(): String = TelaEngine.ensure(applicationContext)

    /**
     * Never: the engine is the process's, not this screen's. Destroying it with
     * the activity is the behaviour [getCachedEngineId] exists to undo.
     */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    /**
     * Asks for the notification permission the background work runs behind.
     *
     * Here rather than at the moment a move starts, because the queue drains
     * from the composition root with no screen of its own to ask from — and by
     * the time there is background work to announce, an activity may be the one
     * thing missing. Android stops showing the dialog once the user has refused
     * twice, so a launch that is already answered costs nothing.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (NotificationPermission.isMissing(this)) {
            requestPermissions(arrayOf(NotificationPermission.NAME), NotificationPermission.REQUEST)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WALLPAPER_CHANNEL,
        ).setMethodCallHandler(::handleWallpaperCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCREEN_CHANNEL,
        ).setMethodCallHandler(::handleScreenCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL,
        ).setMethodCallHandler(::handleShareCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATIONS_CHANNEL,
        ).setMethodCallHandler(::handleNotificationsCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BEAM_CHANNEL,
        ).setMethodCallHandler(::handleBeamCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ROTATION_CHANNEL,
        ).setMethodCallHandler(::handleRotationCall)
        TelaEngine.imageStore?.prompts = this
    }

    /**
     * Hands the engine back with nothing of this activity left on it.
     *
     * The engine is reused by the next launch, so a handler left behind here
     * would hold a destroyed activity — its window and its whole view hierarchy
     * — for as long as a backgrounded batch keeps the process alive, which is
     * exactly the memory [DownloadQueueService] is asking the OS not to reclaim.
     *
     * The three channels are cleared rather than pointed at a stand-in: every
     * one of them is a screen doing something (apply, share, FLAG_SECURE), so a
     * call arriving with no screen is a bug, and a `MissingPluginException`
     * naming the channel is a better way to find it than a quiet failure code.
     */
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        val channels =
            listOf(
                WALLPAPER_CHANNEL,
                SCREEN_CHANNEL,
                SHARE_CHANNEL,
                NOTIFICATIONS_CHANNEL,
                BEAM_CHANNEL,
                ROTATION_CHANNEL,
            )
        for (channel in channels) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
                .setMethodCallHandler(null)
        }
        if (TelaEngine.imageStore?.prompts === this) TelaEngine.imageStore?.prompts = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /**
     * Turns FLAG_SECURE on and off for the private library.
     *
     * The flag belongs to the window, not to a route, so the screen that needs
     * it asks for it on the way in and gives it back on the way out. Left on, it
     * would block screenshots of the whole app; never set, an explicit wallpaper
     * would sit in the app-switcher thumbnail for anyone to see.
     */
    private fun handleScreenCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "setSecure") {
            result.notImplemented()
            return
        }
        if (call.argument<Boolean>("secure") == true) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        result.success(null)
    }

    /**
     * Answers the notification row in Settings, and takes it where it can act.
     *
     * `openSettings` rather than a setter: Android has no API for an app to
     * enable or disable its own notifications. See [NotificationSettings].
     */
    /**
     * Holds and drops the Wi-Fi multicast lock around a beam discovery.
     *
     * Only the lock lives natively — the protocol itself is plain Dart. Without
     * it Android drops the very packets discovery listens for, and the chooser
     * is empty with nothing anywhere to say why. See [MulticastLease].
     */
    /**
     * Starts, stops and describes the auto-rotate schedule.
     *
     * The rotation itself runs in [WallpaperRotationWorker] with no Dart alive,
     * so nothing here ever changes a wallpaper — this is only the schedule.
     */
    private fun handleRotationCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                RotationSchedule.start(
                    context = this,
                    intervalMinutes = (call.argument<Number>("intervalMinutes") ?: 0).toLong(),
                    tier = call.argument<String>("tier") ?: return result.error(
                        "bad_arguments", "tier is required", null,
                    ),
                    target = call.argument<String>("target") ?: return result.error(
                        "bad_arguments", "target is required", null,
                    ),
                )
                result.success(null)
            }
            "stop" -> {
                RotationSchedule.stop(this)
                result.success(null)
            }
            "current" -> result.success(RotationSchedule.current(this))
            else -> result.notImplemented()
        }
    }

    private fun handleBeamCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquireMulticastLock" -> result.success(MulticastLease.acquire(this))
            "releaseMulticastLock" -> {
                MulticastLease.release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleNotificationsCall(call: MethodCall, result: MethodChannel.Result) {
        val notifications = NotificationSettings(this)
        when (call.method) {
            "areEnabled" -> result.success(mapOf("enabled" to notifications.areEnabled()))
            "openSettings" -> result.success(mapOf("opened" to notifications.open()))
            else -> result.notImplemented()
        }
    }

    /**
     * Both executors here are the screen's own work — an apply, a share — so
     * both stop with it. Nothing a download needs runs on them any more: the
     * download pool is [Downloads.executor] and the storage thread belongs to
     * [ImageStoreChannel], because a queue whose whole promise is outliving the
     * screen cannot own its threads from an activity.
     */
    override fun onDestroy() {
        wallpaperExecutor.shutdown()
        shareExecutor.shutdown()
        super.onDestroy()
    }

    /**
     * Opens the SAF folder picker for the Settings device/card chooser.
     *
     * One at a time: a second request while one is pending is refused rather
     * than overwriting it, which would strand the first caller's answer. The
     * launch is guarded because an uncaught throw here is on the main thread and
     * would kill the app — a device with no DocumentsUI has nowhere to send it.
     */
    override fun askFolderGrant(intent: Intent, onAnswer: (Uri?, Int) -> Unit): Boolean {
        if (pendingFolderGrant != null) return false
        pendingFolderGrant = onAnswer
        return try {
            startActivityForResult(intent, OUTSIDE_GALLERY_DIRECTORY_REQUEST)
            true
        } catch (_: Exception) {
            pendingFolderGrant = null
            false
        }
    }

    /** Shows the OS's own delete confirmation. One at a time, as above. */
    override fun askDeleteConfirmation(
        request: IntentSender,
        onAnswer: (Boolean) -> Unit,
    ): Boolean {
        if (pendingDeleteConfirmation != null) return false
        pendingDeleteConfirmation = onAnswer
        return try {
            startIntentSenderForResult(request, GALLERY_DELETE_REQUEST, null, 0, 0, 0)
            true
        } catch (_: Exception) {
            pendingDeleteConfirmation = null
            false
        }
    }

    /**
     * Reads both prompts' outcomes and hands them back to [ImageStoreChannel].
     *
     * A dismissed prompt is an answer, not a failure: the folder grant reports a
     * null tree and the delete reports false, and the channel decides what that
     * means for the batch.
     */
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            OUTSIDE_GALLERY_DIRECTORY_REQUEST -> {
                val answer = pendingFolderGrant ?: return
                pendingFolderGrant = null
                val granted = if (resultCode == RESULT_OK) data?.data else null
                answer(granted, data?.flags ?: 0)
            }
            GALLERY_DELETE_REQUEST -> {
                val answer = pendingDeleteConfirmation ?: return
                pendingDeleteConfirmation = null
                answer(resultCode == RESULT_OK)
            }
        }
    }

    /**
     * Hands a wallpaper to another app — through Android's chooser, or through
     * the clipboard.
     *
     * A link resolves on the UI thread — it launches an intent and nothing more.
     * Anything carrying pixels must first be downloaded, so it runs on
     * [shareExecutor] and hops back for the hand-off itself, which Android
     * requires on the UI thread (see [handOffImage]).
     */
    private fun handleShareCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shareLink" -> handleShareLink(call, result)
            "shareImage" -> handleShareImage(call, result)
            "copyImage" -> handleCopyImage(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleShareLink(call: MethodCall, result: MethodChannel.Result) {
        val page = call.argument<String>("page") ?: run {
            result.success(failure("noTarget"))
            return
        }
        result.success(WallpaperSharing(this).shareLink(page))
    }

    private fun handleShareImage(call: MethodCall, result: MethodChannel.Result) {
        val sharing = WallpaperSharing(this)
        handOffImage(call, result, sharing::downloadToShareCache) { file, _ ->
            sharing.shareImageFile(file)
        }
    }

    private fun handleCopyImage(call: MethodCall, result: MethodChannel.Result) {
        val clipboard = WallpaperClipboard(this)
        // Absent reads as sensitive, not as ordinary: a copy tela cannot classify
        // is one whose preview is better left unshown.
        val sensitive = call.argument<String>("sensitive") != false.toString()
        handOffImage(call, result, clipboard::downloadToClipboardCache) { file, fileName ->
            clipboard.copyToClipboard(file, fileName, sensitive)
        }
    }

    /**
     * Fetches the call's image with [download] off the UI thread, then hands it
     * over with [give] back on it.
     *
     * The split is what both pixel hand-offs need and neither may skip: Android
     * refuses network work on the main thread, and refuses a chooser launch or
     * a clipboard write anywhere else.
     */
    private fun handOffImage(
        call: MethodCall,
        result: MethodChannel.Result,
        download: (String, String) -> File?,
        give: (File, String) -> Map<String, Any>,
    ) {
        val source = call.argument<String>("source")
        val fileName = call.argument<String>("fileName")
        if (source == null || fileName == null) {
            result.success(failure("downloadFailed"))
            return
        }
        shareExecutor.execute {
            val file = download(source, fileName)
            runOnUiThread {
                result.success(file?.let { give(it, fileName) } ?: failure("downloadFailed"))
            }
        }
    }

    private fun handleWallpaperCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "applyWallpaper" -> handleApplyWallpaper(call, result)
            "applyCroppedWallpaper" -> handleApplyCroppedWallpaper(call, result)
            "adjustWallpaper" -> handleAdjustWallpaper(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleApplyWallpaper(call: MethodCall, result: MethodChannel.Result) {
        val source = call.argument<String>("source")
        val target = call.argument<String>("target")
        if (source == null || target == null) {
            result.success(failure("unsupported"))
            return
        }
        wallpaperExecutor.execute {
            val response = applyWallpaper(Uri.parse(source), target)
            runOnUiThread { result.success(response) }
        }
    }

    /**
     * Applies a crop the user framed in tela's own editor.
     *
     * Same fetch-then-apply shape as [handleApplyWallpaper], off the UI thread;
     * only the apply differs — a region decode rather than a whole-image stream.
     */
    private fun handleApplyCroppedWallpaper(call: MethodCall, result: MethodChannel.Result) {
        val source = call.argument<String>("source")
        val target = call.argument<String>("target")
        val region = cropRectFrom(call)
        if (source == null || target == null || region == null) {
            result.success(failure("unsupported"))
            return
        }
        wallpaperExecutor.execute {
            val response = applyCroppedWallpaper(Uri.parse(source), target, region)
            runOnUiThread { result.success(response) }
        }
    }

    private fun cropRectFrom(call: MethodCall): Rect? {
        val left = call.argument<String>("left")?.toIntOrNull() ?: return null
        val top = call.argument<String>("top")?.toIntOrNull() ?: return null
        val width = call.argument<String>("width")?.toIntOrNull() ?: return null
        val height = call.argument<String>("height")?.toIntOrNull() ?: return null
        if (width <= 0 || height <= 0) return null
        return Rect(left, top, left + width, top + height)
    }

    private fun applyCroppedWallpaper(source: Uri, target: String, region: Rect): Map<String, Any> {
        val remote = source.scheme == "http" || source.scheme == "https"
        val cachedImage = try {
            if (remote) downloadToCache(source.toString()) else copyLocalToCache(source)
        } catch (_: Exception) {
            return failure(if (remote) "downloadFailed" else "sourceUnreadable")
        }
        return try {
            WallpaperCropApplying(this).apply(cachedImage, region, target)
            mapOf("success" to true)
        } catch (_: Exception) {
            failure("applyFailed")
        } finally {
            cachedImage.delete()
        }
    }

    /**
     * Hands the image to Android's own crop-and-set editor.
     *
     * Same shape as handleShareImage, and for the same reason: the download
     * must leave the UI thread and starting the activity must return to it.
     */
    private fun handleAdjustWallpaper(call: MethodCall, result: MethodChannel.Result) {
        val source = call.argument<String>("source")
        val fileName = call.argument<String>("fileName")
        if (source == null || fileName == null) {
            result.success(failure("downloadFailed"))
            return
        }
        wallpaperExecutor.execute {
            val editing = SystemWallpaperEditing(this)
            val file = editing.downloadToCache(source, fileName)
            runOnUiThread {
                val response = if (file == null) {
                    failure("downloadFailed")
                } else {
                    editing.openEditorOn(file)
                }
                result.success(response)
            }
        }
    }

    /**
     * Applies a wallpaper from Wallhaven, or from a file already on this device.
     *
     * A past download is set again from its own file: re-fetching several
     * megabytes tela already wrote is both slow and pointless, and it would make
     * "set again" need a network the user may not have. Which failure comes back
     * matters — an unreadable local file is how Dart learns the download was
     * deleted behind our back and that it should fall back to the source URL.
     */
    private fun applyWallpaper(source: Uri, target: String): Map<String, Any> {
        val remote = source.scheme == "http" || source.scheme == "https"
        val cachedImage = try {
            if (remote) downloadToCache(source.toString()) else copyLocalToCache(source)
        } catch (_: Exception) {
            return failure(if (remote) "downloadFailed" else "sourceUnreadable")
        }
        return try {
            applyCachedWallpaper(cachedImage, target)
            mapOf("success" to true)
        } catch (_: Exception) {
            failure("applyFailed")
        } finally {
            cachedImage.delete()
        }
    }

    private fun downloadToCache(imageUrl: String): File {
        val cachedImage = File.createTempFile("tela-wallpaper-", ".image", cacheDir)
        try {
            Downloads.fetch(imageUrl, cachedImage)
            return cachedImage
        } catch (error: Exception) {
            cachedImage.delete()
            throw error
        }
    }

    /**
     * Reads through the ContentResolver, which covers all three storage tiers:
     * a MediaStore image tela inserted, a document under the user's SAF tree, and
     * a plain file in app-private storage. Throws when the file is gone.
     */
    private fun copyLocalToCache(source: Uri): File {
        val stream = contentResolver.openInputStream(source)
            ?: throw IllegalStateException("no input stream for the stored image")
        return stream.use(::copyToCache)
    }

    private fun copyToCache(input: InputStream): File {
        val cachedImage = File.createTempFile("tela-wallpaper-", ".image", cacheDir)
        try {
            cachedImage.outputStream().use { output -> input.copyTo(output) }
            return cachedImage
        } catch (error: Exception) {
            cachedImage.delete()
            throw error
        }
    }

    /**
     * Delegates to [WallpaperSetting], which the rotation worker also uses.
     *
     * One path rather than two: the OEM sequential-write quirk lives there, and
     * a second copy here would drift from it silently.
     */
    private fun applyCachedWallpaper(cachedImage: File, target: String) {
        WallpaperSetting.apply(this, target) { cachedImage.inputStream() }
    }

    private fun failure(code: String): Map<String, Any> = mapOf(
        "success" to false,
        "errorCode" to code,
    )

    private companion object {
        const val WALLPAPER_CHANNEL = "cc.pym.tela/wallpaper"
        const val SCREEN_CHANNEL = "cc.pym.tela/screen"
        const val SHARE_CHANNEL = "cc.pym.tela/share"
        const val NOTIFICATIONS_CHANNEL = "cc.pym.tela/notifications"
        const val BEAM_CHANNEL = "cc.pym.tela/beam"
        const val ROTATION_CHANNEL = "cc.pym.tela/rotation"
        const val OUTSIDE_GALLERY_DIRECTORY_REQUEST = 401
        const val GALLERY_DELETE_REQUEST = 402
    }
}
