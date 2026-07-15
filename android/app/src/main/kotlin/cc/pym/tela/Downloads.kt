package cc.pym.tela

import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Streams a remote image into a local file.
 *
 * Shared by the wallpaper-apply path (which caches a temp file to hand to
 * WallpaperManager) and the share-image path (which caches a named file to
 * expose through a FileProvider), so the HTTP handling lives in one place.
 */
object Downloads {
    private const val TIMEOUT_MS = 30_000

    /** Downloads [imageUrl] into [into], following redirects. Throws on failure. */
    fun fetch(imageUrl: String, into: File) {
        val connection = URL(imageUrl).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.instanceFollowRedirects = true
            connection.inputStream.use { input ->
                into.outputStream().use { output -> input.copyTo(output) }
            }
        } finally {
            connection.disconnect()
        }
    }
}
