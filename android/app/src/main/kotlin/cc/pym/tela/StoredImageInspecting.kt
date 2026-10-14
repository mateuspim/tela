package cc.pym.tela

import android.content.Context
import android.net.Uri
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.channels.FileChannel

/**
 * Reads just enough of a stored image for [ImageCompleteness] to judge it.
 *
 * Two reads in the common case — the first [ImageCompleteness.HEAD_BYTES] and
 * the last two — because a library of thousands is inspected in one pass and
 * almost every JPEG ends exactly on its marker. Only a file that does not pays
 * for the [ImageCompleteness.TAIL_WINDOW] read.
 *
 * Every failure to open is [ImageCompleteness.UNREADABLE], never a throw and
 * never "broken": a revoked grant or an ejected card is not a damaged file, and
 * the repair must not delete what it merely could not see.
 *
 * ```
 * StoredImageInspecting(context).inspect(location) // "intact"
 * ```
 */
internal class StoredImageInspecting(private val context: Context) {
    /** The verdict for the image at [location]. */
    fun inspect(location: Uri): String = try {
        context.contentResolver.openFileDescriptor(location, "r")?.use { descriptor ->
            FileInputStream(descriptor.fileDescriptor).channel.use(::judge)
        } ?: ImageCompleteness.UNREADABLE
    } catch (_: Exception) {
        ImageCompleteness.UNREADABLE
    }

    private fun judge(channel: FileChannel): String {
        val size = channel.size()
        if (size == 0L) return ImageCompleteness.EMPTY
        val head = channel.readAt(0, ImageCompleteness.HEAD_BYTES)
        if (ImageCompleteness.endsCleanly(head, channel.readTail(size, 2))) {
            return ImageCompleteness.INTACT
        }
        return ImageCompleteness.judge(size, head, channel.readTail(size, ImageCompleteness.TAIL_WINDOW))
    }

    private fun FileChannel.readTail(size: Long, count: Int): ByteArray {
        val length = minOf(size, count.toLong()).toInt()
        return readAt(size - length, length)
    }

    /** Up to [count] bytes from [position]; shorter only at end of file. */
    private fun FileChannel.readAt(position: Long, count: Int): ByteArray {
        val buffer = ByteBuffer.allocate(count)
        while (buffer.hasRemaining()) {
            if (read(buffer, position + buffer.position()) < 0) break
        }
        return buffer.array().copyOf(buffer.position())
    }
}
