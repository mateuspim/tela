package cc.pym.tela

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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WALLPAPER_CHANNEL,
        ).setMethodCallHandler(::handleWallpaperCall)
    }

    override fun onDestroy() {
        wallpaperExecutor.shutdown()
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

    private companion object {
        const val WALLPAPER_CHANNEL = "cc.pym.tela/wallpaper"
        const val NETWORK_TIMEOUT_MS = 30_000
        const val BETWEEN_TARGETS_DELAY_MS = 500L
    }
}
