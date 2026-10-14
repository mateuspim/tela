package cc.pym.tela

import java.io.BufferedInputStream
import java.io.InputStream

/**
 * Where two streams disagree: the first and last differing offsets and how
 * many bytes differ in between.
 *
 * Diagnosis for [StoredCopyMismatch], which on the SM-X730 fired for 39 copies
 * whose readback was exactly as long as the source (owner, 2026-10-07). A
 * same-length mismatch is either the platform rewriting metadata on read —
 * confined to the first few KB — or the card corrupting data, scattered
 * anywhere; these three numbers tell the two apart without naming the file.
 */
internal class ByteDifference(val firstAt: Long, val lastAt: Long, val count: Long) {
    companion object {
        /** Compares [a] and [b] to the end of the shorter; null when they agree. */
        fun between(a: InputStream, b: InputStream): ByteDifference? {
            val left = BufferedInputStream(a)
            val right = BufferedInputStream(b)
            var offset = 0L
            var first = -1L
            var last = -1L
            var count = 0L
            while (true) {
                val x = left.read()
                val y = right.read()
                if (x < 0 || y < 0) break
                if (x != y) {
                    if (first < 0) first = offset
                    last = offset
                    count++
                }
                offset++
            }
            return if (count == 0L) null else ByteDifference(first, last, count)
        }
    }
}
