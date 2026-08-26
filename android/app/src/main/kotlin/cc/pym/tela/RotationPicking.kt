package cc.pym.tela

/**
 * Which wallpaper the next rotation should use.
 *
 * Pure — no Android, no filesystem — so the suite exercises it without
 * Robolectric, the same shape [ThumbnailSampling] takes. Everything that can
 * actually go wrong about rotation order is decidable here: running off the end
 * of the list, a list that shrank since the last run, and a list of one.
 */
internal object RotationPicking {
    /**
     * The index to show next, given how many candidates there are now and which
     * one was shown last.
     *
     * [lastIndex] is the *stored* cursor, which may be stale: files get deleted
     * between runs, so it can point past the end of a list that shrank. That
     * wraps to 0 rather than failing — a rotation that stops rotating because
     * someone deleted a wallpaper would be a silent death, and the cursor is a
     * convenience, not a record worth preserving.
     *
     * Answers -1 for an empty list, which the caller reads as "nothing to do"
     * rather than an error: an empty download folder is an ordinary state.
     *
     * ```
     * RotationPicking.next(count = 3, lastIndex = 2) // 0
     * ```
     */
    fun next(count: Int, lastIndex: Int): Int {
        if (count <= 0) return -1
        // A single candidate re-applies itself. Deliberate: the alternative is
        // doing nothing, which looks identical to a broken schedule from the
        // outside, and re-applying is harmless.
        if (count == 1) return 0
        val from = if (lastIndex < 0 || lastIndex >= count) -1 else lastIndex
        return (from + 1) % count
    }
}
