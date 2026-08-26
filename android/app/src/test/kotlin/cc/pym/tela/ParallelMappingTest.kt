package cc.pym.tela

import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The one property parallelising a listing must not cost: its order.
 *
 * A vault listing is a shelf. Collecting rows as they finish rather than as
 * they were asked for would shuffle it differently on every read, which is
 * worse than the slowness it was meant to fix.
 */
class ParallelMappingTest {
    @Test
    fun `keeps the order it was given, whatever order the work finishes in`() {
        // The first item is the slowest, so a "collect as they complete"
        // implementation would put it last.
        val items = (1..24).toList()
        val mapped = mapInParallel(items, workers = 8) { n ->
            if (n == 1) Thread.sleep(120)
            n * 2
        }

        assertEquals(items.map { it * 2 }, mapped)
    }

    @Test
    fun `drops the items the transform rejects`() {
        val mapped = mapInParallel((1..10).toList(), workers = 4) { n ->
            if (n % 2 == 0) n else null
        }

        assertEquals(listOf(2, 4, 6, 8, 10), mapped)
    }

    @Test
    fun `really does run several at once`() {
        val running = AtomicInteger(0)
        val mostAtOnce = AtomicInteger(0)

        mapInParallel((1..16).toList(), workers = 4) { n ->
            val now = running.incrementAndGet()
            mostAtOnce.updateAndGet { seen -> maxOf(seen, now) }
            Thread.sleep(40)
            running.decrementAndGet()
            n
        }

        assertTrue("saw ${mostAtOnce.get()} at once", mostAtOnce.get() > 1)
    }

    @Test
    fun `an empty list needs no threads at all`() {
        assertEquals(emptyList<Int>(), mapInParallel(emptyList<Int>(), workers = 8) { it })
    }

    /** One worker is an ordinary map, and must stay one — no pool, no hand-off. */
    @Test
    fun `a single worker maps in place`() {
        val threads = mutableSetOf<Long>()

        mapInParallel((1..5).toList(), workers = 1) { n ->
            threads.add(Thread.currentThread().id)
            n
        }

        assertEquals(setOf(Thread.currentThread().id), threads)
    }
}
