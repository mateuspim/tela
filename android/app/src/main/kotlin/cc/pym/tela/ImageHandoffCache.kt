package cc.pym.tela

import android.content.Context
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

/**
 * Stages one image in a cache folder and names it for another app to read.
 *
 * Every way tela hands real pixels to a stranger — the share sheet, the system
 * wallpaper editor, the clipboard — takes the same three steps: empty the
 * folder, fetch the bytes, expose them through the FileProvider. The emptying
 * is why this is one class rather than three copies: it is what stops a past
 * hand-off piling up in cache, so only the image being handed out right now is
 * ever exposed, and a privacy rule like that is worth having exactly one home.
 *
 * Each caller passes its own [directory]. Sharing one would make the callers
 * delete the file out from under each other, since each wipes on the way in.
 * Every directory used here must also appear in res/xml/file_paths.xml, or
 * [contentUri] throws.
 */
class ImageHandoffCache(
    private val context: Context,
    private val directory: String,
) {
    /**
     * Downloads [imageUrl] into the folder under [fileName], returning the file
     * or null when the fetch fails. Run this off the UI thread.
     */
    fun download(imageUrl: String, fileName: String): File? {
        val file = emptiedFolderFile(fileName)
        return try {
            Downloads.fetch(imageUrl, file)
            file
        } catch (_: Exception) {
            file.delete()
            null
        }
    }

    /** A content URI for [file] that another app can read, once granted. */
    fun contentUri(file: File): Uri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        file,
    )

    private fun emptiedFolderFile(fileName: String): File {
        val folder = File(context.cacheDir, directory)
        folder.mkdirs()
        folder.listFiles()?.forEach { it.delete() }
        return File(folder, fileName)
    }
}
