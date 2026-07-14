package cc.pym.tela

import android.content.Intent
import android.net.Uri
import android.app.WallpaperManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val wallpaperExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val imageStoreExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var pendingOutsideGalleryStore: PendingOutsideGalleryStore? = null

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
    }

    override fun onDestroy() {
        wallpaperExecutor.shutdown()
        imageStoreExecutor.shutdown()
        super.onDestroy()
    }

    private fun handleWallpaperCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "applyWallpaper") {
            result.notImplemented()
            return
        }
        val imageUrl = call.argument<String>("imageUrl")
        val target = call.argument<String>("target")
        if (imageUrl == null || target == null) {
            result.success(failure("unsupported"))
            return
        }
        wallpaperExecutor.execute {
            val response = applyRemoteWallpaper(imageUrl, target)
            runOnUiThread { result.success(response) }
        }
    }

    private fun handleImageStoreCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "storeImage") {
            result.notImplemented()
            return
        }
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

    private fun imageStoreRequest(call: MethodCall): ImageStoreRequest? {
        val id = call.argument<String>("id") ?: return null
        val imageUrl = call.argument<String>("imageUrl") ?: return null
        val purity = call.argument<String>("purity") ?: return null
        val tier = call.argument<String>("tier") ?: return null
        return ImageStoreRequest(id, imageUrl, purity, tier)
    }

    private fun requestOutsideGalleryDirectory(
        request: ImageStoreRequest,
        result: MethodChannel.Result,
    ) {
        if (pendingOutsideGalleryStore != null) {
            result.success(imageStoreFailure("notConfigured"))
            return
        }
        pendingOutsideGalleryStore = PendingOutsideGalleryStore(request, result)
        startActivityForResult(
            Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(DIRECTORY_ACCESS_FLAGS),
            OUTSIDE_GALLERY_DIRECTORY_REQUEST,
        )
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != OUTSIDE_GALLERY_DIRECTORY_REQUEST) return
        val pending = pendingOutsideGalleryStore ?: return
        pendingOutsideGalleryStore = null
        val tree = data?.data
        if (resultCode != RESULT_OK || tree == null || !saveOutsideGalleryTree(tree, data.flags)) {
            pending.result.success(imageStoreFailure("notConfigured"))
            return
        }
        storeImage(pending.request, pending.result)
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

    private fun applyRemoteWallpaper(imageUrl: String, target: String): Map<String, Any> {
        val cachedImage = try {
            downloadToCache(imageUrl)
        } catch (_: Exception) {
            return failure("downloadFailed")
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
        val connection = URL(imageUrl).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = NETWORK_TIMEOUT_MS
            connection.readTimeout = NETWORK_TIMEOUT_MS
            connection.instanceFollowRedirects = true
            connection.inputStream.use { input ->
                cachedImage.outputStream().use { output -> input.copyTo(output) }
            }
            return cachedImage
        } catch (error: Exception) {
            cachedImage.delete()
            throw error
        } finally {
            connection.disconnect()
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

    private data class PendingOutsideGalleryStore(
        val request: ImageStoreRequest,
        val result: MethodChannel.Result,
    )

    private companion object {
        const val WALLPAPER_CHANNEL = "cc.pym.tela/wallpaper"
        const val IMAGE_STORE_CHANNEL = "cc.pym.tela/images"
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
        const val NETWORK_TIMEOUT_MS = 30_000
        const val BETWEEN_TARGETS_DELAY_MS = 500L
    }
}
