package cc.pym.tela

import java.util.concurrent.Callable
import java.util.concurrent.Executors

/**
 * Maps a list several items at a time, **keeping the order it was given**.
 *
 * For work that is spent waiting rather than computing: a SAF header read is a
 * binder round trip, and a few thousand of them in a row is minutes the user
 * watches a spinner for. See [SafVaultListing.list], which is why this exists.
 *
 * Order is the property worth naming. `invokeAll` answers futures in the order
 * the tasks were submitted whatever order they finish in, so a caller that
 * sorts afterwards is unaffected and one that does not still gets its listing
 * back the way the directory gave it. A hand-rolled "collect as they finish"
 * would silently shuffle a shelf.
 *
 * Nulls are dropped, so a transform may reject an item — the same shape
 * `mapNotNull` has.
 *
 * ```
 * mapInParallel(files, workers = 8) { file -> describe(file) }
 * ```
 */
internal fun <T, R : Any> mapInParallel(
    items: List<T>,
    workers: Int,
    transform: (T) -> R?,
): List<R> {
    if (items.isEmpty()) return emptyList()
    if (workers <= 1 || items.size == 1) return items.mapNotNull(transform)
    val pool = Executors.newFixedThreadPool(minOf(workers, items.size))
    return try {
        pool.invokeAll(items.map { item -> Callable { transform(item) } })
            .mapNotNull { done -> done.get() }
    } finally {
        pool.shutdown()
    }
}
