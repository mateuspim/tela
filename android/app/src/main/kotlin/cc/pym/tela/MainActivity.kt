package cc.pym.tela

import android.content.Intent
import android.graphics.Rect
import android.net.Uri
import android.app.WallpaperManager
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
 */
class MainActivity : FlutterFragmentActivity() {
    private val wallpaperExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val imageStoreExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val shareExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var pendingOutsideGalleryGrant: PendingOutsideGalleryGrant? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WALLPAPER_CHANNEL,
        ).setMethodCallHandler(::handleWallpaperCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            IMAGE_STORE_CHANNEL,
        ).setMethodCallHandler(::handleImageStoreCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCREEN_CHANNEL,
        ).setMethodCallHandler(::handleScreenCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL,
        ).setMethodCallHandler(::handleShareCall)
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

    override fun onDestroy() {
        wallpaperExecutor.shutdown()
        imageStoreExecutor.shutdown()
        shareExecutor.shutdown()
        super.onDestroy()
    }

    /**
     * Shares a wallpaper out through Android's chooser.
     *
     * A link resolves on the UI thread — it launches an intent and nothing more.
     * An image must first be downloaded, so it runs on [shareExecutor] and hops
     * back to launch the chooser, which Android requires on the UI thread.
     */
    private fun handleShareCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shareLink" -> handleShareLink(call, result)
            "shareImage" -> handleShareImage(call, result)
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
        val source = call.argument<String>("source")
        val fileName = call.argument<String>("fileName")
        if (source == null || fileName == null) {
            result.success(failure("downloadFailed"))
            return
        }
        shareExecutor.execute {
            val sharing = WallpaperSharing(this)
            val file = sharing.downloadToShareCache(source, fileName)
            runOnUiThread {
                val response = if (file == null) {
                    failure("downloadFailed")
                } else {
                    sharing.shareImageFile(file)
                }
                result.success(response)
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

    private fun handleImageStoreCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "storeImage" -> handleStoreImage(call, result)
            "listPrivateImages" -> onStorageThread(result) { ImageStorage(this).listPrivate() }
            "deletePrivateImage" -> handleDeletePrivateImage(call, result)
            "canReadImage" -> handleCanReadImage(call, result)
            "materializeImage" -> handleMaterializeImage(call, result)
            "releasePreview" -> handleReleasePreview(call, result)
            "describeDownloadLocation" -> handleDescribeDownloadLocation(result)
            "chooseDownloadFolder" -> handleChooseDownloadFolder(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleMaterializeImage(call: MethodCall, result: MethodChannel.Result) {
        val location = call.argument<String>("location") ?: run {
            result.success(mapOf("success" to false))
            return
        }
        onStorageThread(result) { ImageStorage(this).materialise(Uri.parse(location)) }
    }

    private fun handleReleasePreview(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path") ?: run {
            result.success(mapOf("success" to true))
            return
        }
        onStorageThread(result) { ImageStorage(this).releasePreview(path) }
    }

    private fun handleCanReadImage(call: MethodCall, result: MethodChannel.Result) {
        val location = call.argument<String>("location") ?: run {
            result.success(mapOf("success" to true, "readable" to false))
            return
        }
        onStorageThread(result) { ImageStorage(this).canRead(Uri.parse(location)) }
    }

    private fun handleStoreImage(call: MethodCall, result: MethodChannel.Result) {
        val request = imageStoreRequest(call) ?: run {
            result.success(imageStoreFailure("unavailable"))
            return
        }
        if (request.tier == "filesOutsideGallery" && outsideGalleryTree() == null) {
            requestOutsideGalleryDirectory(request, result)
            return
        }
        storeImage(request, result)
    }

    /** Describes the location off the UI thread; it does filesystem stats. */
    private fun handleDescribeDownloadLocation(result: MethodChannel.Result) {
        onStorageThread(result) {
            DownloadFolderDescribing(this).describe(outsideGalleryTree())
        }
    }

    /**
     * Opens the folder picker pointed at the chosen volume, no download waiting.
     *
     * The `kind` ("device" or "sdCard") pre-aims the picker so the user confirms
     * one folder instead of hunting through a blank tree browser — the whole
     * point of the device/card choice. A card asked for while the slot is empty
     * has no volume to aim at, so it answers `notConfigured` rather than opening
     * a picker that could land anywhere.
     */
    private fun handleChooseDownloadFolder(call: MethodCall, result: MethodChannel.Result) {
        val kind = call.argument<String>("kind") ?: run {
            result.success(imageStoreFailure("unavailable"))
            return
        }
        val intent = DownloadVolumes(this).openTreeIntentFor(kind) ?: run {
            result.success(imageStoreFailure("notConfigured"))
            return
        }
        requestOutsideGalleryDirectory(null, result, intent)
    }

    private fun handleDeletePrivateImage(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id") ?: run {
            result.success(imageStoreFailure("unavailable"))
            return
        }
        onStorageThread(result) { ImageStorage(this).deletePrivate(id) }
    }

    /** Runs filesystem work off the UI thread, answering on it. */
    private fun onStorageThread(
        result: MethodChannel.Result,
        work: () -> Map<String, Any>,
    ) {
        imageStoreExecutor.execute {
            val response = try {
                work()
            } catch (_: Exception) {
                imageStoreFailure("unavailable")
            }
            runOnUiThread { result.success(response) }
        }
    }

    private fun imageStoreRequest(call: MethodCall): ImageStoreRequest? {
        val id = call.argument<String>("id") ?: return null
        val imageUrl = call.argument<String>("imageUrl") ?: return null
        val purity = call.argument<String>("purity") ?: return null
        val tier = call.argument<String>("tier") ?: return null
        return ImageStoreRequest(id, imageUrl, purity, tier)
    }

    /**
     * Starts the folder picker, for a waiting [request] or for its own sake when
     * null.
     *
     * [intent] lets Settings pass a picker already aimed at a chosen volume; the
     * download-time fallback passes null and gets the plain, un-aimed tree
     * picker. Either way the persistable-grant flags are added here so no caller
     * can forget them.
     */
    private fun requestOutsideGalleryDirectory(
        request: ImageStoreRequest?,
        result: MethodChannel.Result,
        intent: Intent? = null,
    ) {
        if (pendingOutsideGalleryGrant != null) {
            result.success(imageStoreFailure("notConfigured"))
            return
        }
        pendingOutsideGalleryGrant = PendingOutsideGalleryGrant(request, result)
        val picker = (intent ?: Intent(Intent.ACTION_OPEN_DOCUMENT_TREE))
            .addFlags(DIRECTORY_ACCESS_FLAGS)
        startActivityForResult(picker, OUTSIDE_GALLERY_DIRECTORY_REQUEST)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != OUTSIDE_GALLERY_DIRECTORY_REQUEST) return
        val pending = pendingOutsideGalleryGrant ?: return
        pendingOutsideGalleryGrant = null
        val tree = data?.data
        if (resultCode != RESULT_OK || tree == null || !saveOutsideGalleryTree(tree, data.flags)) {
            pending.result.success(imageStoreFailure("notConfigured"))
            return
        }
        val request = pending.request
        // No waiting download means Settings asked: answer with the location it
        // now has, so the screen can redraw without a second round trip.
        if (request == null) handleDescribeDownloadLocation(pending.result)
        else storeImage(request, pending.result)
    }

    private fun saveOutsideGalleryTree(tree: Uri, returnedFlags: Int): Boolean {
        if (tree.authority != EXTERNAL_STORAGE_PROVIDER) return false
        val grantedFlags = returnedFlags and PERSISTED_DIRECTORY_ACCESS_FLAGS
        return try {
            contentResolver.takePersistableUriPermission(tree, grantedFlags)
            getSharedPreferences(PREFERENCES, MODE_PRIVATE)
                .edit()
                .putString(OUTSIDE_GALLERY_TREE, tree.toString())
                .apply()
            true
        } catch (_: SecurityException) {
            false
        }
    }

    private fun outsideGalleryTree(): String? {
        return getSharedPreferences(PREFERENCES, MODE_PRIVATE)
            .getString(OUTSIDE_GALLERY_TREE, null)
    }

    private fun storeImage(request: ImageStoreRequest, result: MethodChannel.Result) {
        imageStoreExecutor.execute {
            val response = ImageStorage(this).store(request, outsideGalleryTree())
            runOnUiThread { result.success(response) }
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

    private fun applyCachedWallpaper(cachedImage: File, target: String) {
        val wallpaper = WallpaperManager.getInstance(this)
        when (target) {
            "home" -> setWallpaper(wallpaper, cachedImage, WallpaperManager.FLAG_SYSTEM)
            "lock" -> setWallpaper(wallpaper, cachedImage, WallpaperManager.FLAG_LOCK)
            "both" -> setBothWallpapers(wallpaper, cachedImage)
            else -> throw IllegalArgumentException("target must be home|lock|both")
        }
    }

    private fun setBothWallpapers(wallpaper: WallpaperManager, cachedImage: File) {
        setWallpaper(wallpaper, cachedImage, WallpaperManager.FLAG_SYSTEM)
        // Restrictive OEMs need distinct writes; a combined flag often changes only home.
        Thread.sleep(BETWEEN_TARGETS_DELAY_MS)
        setWallpaper(wallpaper, cachedImage, WallpaperManager.FLAG_LOCK)
    }

    private fun setWallpaper(wallpaper: WallpaperManager, image: File, flag: Int) {
        image.inputStream().use { stream ->
            wallpaper.setStream(stream, null, true, flag)
        }
    }

    private fun failure(code: String): Map<String, Any> = mapOf(
        "success" to false,
        "errorCode" to code,
    )

    private fun imageStoreFailure(code: String): Map<String, Any> = mapOf(
        "success" to false,
        "errorCode" to code,
    )

    /** A folder picker in flight; [request] is null when nothing waits on it. */
    private data class PendingOutsideGalleryGrant(
        val request: ImageStoreRequest?,
        val result: MethodChannel.Result,
    )

    private companion object {
        const val WALLPAPER_CHANNEL = "cc.pym.tela/wallpaper"
        const val IMAGE_STORE_CHANNEL = "cc.pym.tela/images"
        const val SCREEN_CHANNEL = "cc.pym.tela/screen"
        const val SHARE_CHANNEL = "cc.pym.tela/share"
        const val OUTSIDE_GALLERY_DIRECTORY_REQUEST = 401
        const val PREFERENCES = "tela.storage"
        const val OUTSIDE_GALLERY_TREE = "outsideGalleryTree"
        const val EXTERNAL_STORAGE_PROVIDER = "com.android.externalstorage.documents"
        const val DIRECTORY_ACCESS_FLAGS =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
        const val PERSISTED_DIRECTORY_ACCESS_FLAGS =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        const val BETWEEN_TARGETS_DELAY_MS = 500L
    }
}
