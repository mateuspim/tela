package cc.pym.tela

/**
 * Whether a stored image's bytes look whole, judged from its size and its two
 * ends — no decode, no Android type, so the rule is testable on the JVM.
 *
 * Exists for the broken-image repair: an offload before copies were verified
 * left 0-byte documents on the SM-X730's card whose originals were already
 * gone (owner, 2026-10-07), and nothing in the app could tell them from a
 * wallpaper. "Ends where its format says it must" is the cheap test that also
 * catches a download cut off part-way.
 *
 * **Says [INTACT] whenever it cannot be sure.** A verdict here leads to a file
 * being overwritten or deleted, so an unknown format, and a JPEG whose end
 * marker sits anywhere in the tail window rather than on the last two bytes
 * (some cameras append data after it), both pass.
 *
 * ```
 * ImageCompleteness.judge(size = 0, head = ByteArray(0), tail = ByteArray(0)) // "empty"
 * ```
 */
internal object ImageCompleteness {
    const val INTACT = "intact"
    const val EMPTY = "empty"
    const val TRUNCATED = "truncated"
    const val UNREADABLE = "unreadable"

    /** How many bytes of the start the judge needs. */
    const val HEAD_BYTES = 12

    /** How far back from the end an end marker may sit. */
    const val TAIL_WINDOW = 64 * 1024

    /** The verdict for a file of [size] bytes opening with [head], ending with [tail]. */
    fun judge(size: Long, head: ByteArray, tail: ByteArray): String = when {
        size == 0L -> EMPTY
        isJpeg(head) -> if (tail.containsSequence(JPEG_END)) INTACT else TRUNCATED
        isPng(head) -> if (tail.containsSequence(PNG_END)) INTACT else TRUNCATED
        isWebp(head) -> if (webpDeclaredLength(head) <= size) INTACT else TRUNCATED
        else -> INTACT
    }

    /** Whether the last two bytes alone settle it, sparing the wider read. */
    fun endsCleanly(head: ByteArray, lastTwo: ByteArray): Boolean =
        isJpeg(head) && lastTwo.containsSequence(JPEG_END)

    private fun isJpeg(head: ByteArray): Boolean = head.startsWith(0xFF, 0xD8)

    private fun isPng(head: ByteArray): Boolean = head.startsWith(0x89, 0x50, 0x4E, 0x47)

    private fun isWebp(head: ByteArray): Boolean =
        head.size >= HEAD_BYTES && head.startsWith(0x52, 0x49, 0x46, 0x46) &&
            head.copyOfRange(8, 12).startsWith(0x57, 0x45, 0x42, 0x50)

    /** RIFF's own length field, plus the 8 header bytes it does not count. */
    private fun webpDeclaredLength(head: ByteArray): Long =
        (0 until 4).fold(0L) { sum, i -> sum or ((head[4 + i].toLong() and 0xFF) shl (8 * i)) } + 8

    private fun ByteArray.startsWith(vararg prefix: Int): Boolean =
        size >= prefix.size && prefix.indices.all { this[it] == prefix[it].toByte() }

    private fun ByteArray.containsSequence(sequence: ByteArray): Boolean =
        (0..size - sequence.size).any { start ->
            sequence.indices.all { this[start + it] == sequence[it] }
        }

    private val JPEG_END = byteArrayOf(0xFF.toByte(), 0xD9.toByte())
    private val PNG_END = "IEND".toByteArray(Charsets.US_ASCII)
}
