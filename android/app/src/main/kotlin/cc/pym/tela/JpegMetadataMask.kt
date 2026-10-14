package cc.pym.tela

/**
 * Splits a JPEG stream into what a copy check compares and what it skips: the
 * bodies of APPn and COM segments are skipped, everything else is compared.
 *
 * **Why skip anything.** Android rewrites location metadata on the way *out* of
 * shared storage for an app without `ACCESS_MEDIA_LOCATION`, keeping the
 * length. A copy onto the card was byte-perfect on disk — checked against the
 * Wallhaven original — yet every readback of a photo with GPS differed in 2 to
 * 3572 bytes, all inside an APP1 segment, and 39 offloads failed on it every
 * retry (owner, 2026-10-07). Comparing the metadata compared the platform's
 * redaction, not the card.
 *
 * What still counts: every marker and segment length, the quantisation and
 * Huffman tables, and every byte from start-of-scan to the end — the image. A
 * card that loses or flips image bytes still fails, and the stream lengths are
 * compared separately. Anything that does not open with SOI is passed through
 * whole, so a PNG or WebP keeps the strict check.
 *
 * ```
 * val mask = JpegMetadataMask()
 * mask.feed(buffer, count) { bytes, from, length -> digest.update(bytes, from, length) }
 * ```
 */
internal class JpegMetadataMask {
    private enum class State { SOI_FF, SOI_D8, MARKER_FF, MARKER_ID, LENGTH_HI, LENGTH_LO, BODY, PAYLOAD }

    private var state = State.SOI_FF
    private var marker = 0
    private var lengthHigh = 0
    private var remaining = 0

    /** Passes the compared parts of `buffer[0, count)` to [compared], in order. */
    fun feed(buffer: ByteArray, count: Int, compared: (ByteArray, Int, Int) -> Unit) {
        var index = 0
        while (index < count && state != State.PAYLOAD) {
            if (step(buffer[index].toInt() and 0xFF)) compared(buffer, index, 1)
            index++
        }
        if (index < count) compared(buffer, index, count - index)
    }

    /** Advances over one header byte; answers whether it is compared. */
    private fun step(byte: Int): Boolean {
        when (state) {
            State.SOI_FF -> state = if (byte == 0xFF) State.SOI_D8 else State.PAYLOAD
            State.SOI_D8 -> state = if (byte == 0xD8) State.MARKER_FF else State.PAYLOAD
            State.MARKER_FF -> state = if (byte == 0xFF) State.MARKER_ID else State.PAYLOAD
            State.MARKER_ID -> onMarker(byte)
            State.LENGTH_HI -> {
                lengthHigh = byte
                state = State.LENGTH_LO
            }
            State.LENGTH_LO -> onLength(lengthHigh shl 8 or byte)
            State.BODY -> return onBody()
            State.PAYLOAD -> Unit
        }
        return true
    }

    private fun onMarker(byte: Int) {
        marker = byte
        state = when {
            byte == 0xFF -> State.MARKER_ID // fill byte before the real marker
            byte == SOS || byte == EOI -> State.PAYLOAD
            byte in RST0..RST7 || byte == TEM -> State.MARKER_FF // no length
            else -> State.LENGTH_HI
        }
    }

    private fun onLength(length: Int) {
        remaining = length - 2
        state = when {
            remaining < 0 -> State.PAYLOAD // malformed: compare the rest whole
            remaining == 0 -> State.MARKER_FF
            else -> State.BODY
        }
    }

    private fun onBody(): Boolean {
        remaining--
        if (remaining == 0) state = State.MARKER_FF
        return !(marker in APP0..APP15 || marker == COM)
    }

    private companion object {
        const val SOS = 0xDA
        const val EOI = 0xD9
        const val RST0 = 0xD0
        const val RST7 = 0xD7
        const val TEM = 0x01
        const val APP0 = 0xE0
        const val APP15 = 0xEF
        const val COM = 0xFE
    }
}
