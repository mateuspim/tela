package cc.pym.tela

import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

/**
 * A stream's SHA-256 and how many bytes it held.
 *
 * The hash skips JPEG metadata bodies — see [JpegMetadataMask] for why a
 * byte-exact hash could never pass on a photo with GPS. The length does not
 * skip anything.
 *
 * The length rides along for the failure log, not the comparison: when an SD
 * readback mismatches, "the card holds more bytes than were written" is a
 * truncate the provider skipped, and "fewer" is a write the card lost — two
 * faults with two different fixes, which a bare hash cannot tell apart.
 */
internal class StreamDigest(val sha256: ByteArray, val length: Long) {
    /** Whether [other] hashed the same bytes. */
    fun sameAs(other: StreamDigest?): Boolean =
        other != null && length == other.length && sha256.contentEquals(other.sha256)
}

/** Copies once while computing the exact digest used to verify the SD readback. */
internal fun copyAndDigest(input: InputStream, output: OutputStream): StreamDigest =
    digestWhileReading(input) { buffer, count -> output.write(buffer, 0, count) }

/** Hashes a destination readback without retaining image bytes in memory. */
internal fun digestOf(input: InputStream): StreamDigest = digestWhileReading(input) { _, _ -> }

private fun digestWhileReading(
    input: InputStream,
    onChunk: (ByteArray, Int) -> Unit,
): StreamDigest {
    val digest = MessageDigest.getInstance("SHA-256")
    val mask = JpegMetadataMask()
    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
    var length = 0L
    while (true) {
        val count = input.read(buffer)
        if (count < 0) break
        if (count == 0) continue
        onChunk(buffer, count)
        mask.feed(buffer, count) { bytes, from, size -> digest.update(bytes, from, size) }
        length += count
    }
    return StreamDigest(digest.digest(), length)
}
