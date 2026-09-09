package cc.pym.tela

import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

/** Copies once while computing the exact digest used to verify the SD readback. */
internal fun copyAndDigest(input: InputStream, output: OutputStream): ByteArray {
    val digest = MessageDigest.getInstance("SHA-256")
    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
    while (true) {
        val count = input.read(buffer)
        if (count < 0) break
        if (count == 0) continue
        output.write(buffer, 0, count)
        digest.update(buffer, 0, count)
    }
    return digest.digest()
}

/** Hashes a destination readback without retaining image bytes in memory. */
internal fun digestOf(input: InputStream): ByteArray {
    val digest = MessageDigest.getInstance("SHA-256")
    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
    while (true) {
        val count = input.read(buffer)
        if (count < 0) break
        if (count == 0) continue
        digest.update(buffer, 0, count)
    }
    return digest.digest()
}
