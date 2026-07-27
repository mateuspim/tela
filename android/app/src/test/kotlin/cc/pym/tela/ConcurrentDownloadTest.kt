package cc.pym.tela

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import java.io.File
import java.net.ServerSocket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * What the download queue's speed actually rests on.
 *
 * `MainActivity` used to run every `storeImage` on a single-thread executor, so
 * a batch of downloads serialised there however many Dart ran at once — the
 * Dart-side concurrency bought nothing. The fix is a separate
 * `downloadExecutor` pool, and it is only safe because `ImageStorage.store`
 * holds no mutable state between calls and each wallpaper writes its own file.
 *
 * That last claim is the one worth defending mechanically, so this drives real
 * concurrent stores against a real (loopback) HTTP server and checks every file
 * arrived whole. Only the app-private tier is reachable here: MediaStore and
 * SAF are not usefully emulated under Robolectric — see [ImageStorageTest].
 *
 * Pinned to SDK 35 for the same reason that suite is.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ConcurrentDownloadTest {
    private lateinit var context: Context
    private lateinit var storage: ImageStorage
    private lateinit var server: TinyImageServer

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        storage = ImageStorage(context)
        server = TinyImageServer()
    }

    @After
    fun tearDown() {
        server.close()
    }

    /** The pool and Dart's own cap are the two ends of one pipe. */
    @Test
    fun `the download pool is sized to the queue's concurrency`() {
        assertEquals(3, MAX_CONCURRENT_DOWNLOADS)
    }

    /**
     * Six wallpapers down three threads, all landing intact.
     *
     * The failure this guards against is not a crash: it is two concurrent
     * stores treading on one another's stream and leaving a truncated or
     * interleaved file, which reads back as a corrupt wallpaper rather than as
     * an error.
     */
    @Test
    fun `concurrent stores each write their own file, whole`() {
        val ids = listOf("aaa111", "bbb222", "ccc333", "ddd444", "eee555", "fff666")
        val pool = Executors.newFixedThreadPool(MAX_CONCURRENT_DOWNLOADS)
        val ready = CountDownLatch(ids.size)

        for (id in ids) {
            pool.execute {
                storage.store(request(id), null)
                ready.countDown()
            }
        }

        assertTrue("the stores did not finish", ready.await(30, TimeUnit.SECONDS))
        pool.shutdown()
        for (id in ids) {
            val file = File(File(context.filesDir, "wallpapers"), "wallhaven-$id.jpg")
            assertTrue("missing file for $id", file.exists())
            assertEquals("wrong contents for $id", server.body(id), file.readText())
        }
    }

    /**
     * The same wallpaper twice at once still ends up whole.
     *
     * The Dart queue is idempotent per wallpaper so this should not arise, but
     * a truncated file is a silent, permanent wrong answer and the store must
     * not depend on the caller to avoid it.
     */
    @Test
    fun `two stores of the same wallpaper leave one intact file`() {
        val pool = Executors.newFixedThreadPool(2)
        val ready = CountDownLatch(2)

        repeat(2) {
            pool.execute {
                storage.store(request("aaa111"), null)
                ready.countDown()
            }
        }

        assertTrue("the stores did not finish", ready.await(30, TimeUnit.SECONDS))
        pool.shutdown()
        val file = File(File(context.filesDir, "wallpapers"), "wallhaven-aaa111.jpg")
        assertEquals(server.body("aaa111"), file.readText())
    }

    private fun request(id: String) = ImageStoreRequest(
        source = "wallhaven",
        id = id,
        imageUrl = server.urlFor(id),
        purity = "sfw",
        tier = "appPrivate",
    )
}

/**
 * A loopback HTTP server serving one distinct body per wallpaper id.
 *
 * Robolectric leaves `java.net` alone, and `ImageStorage.copyRemote` speaks
 * plain `HttpURLConnection`, so this is the only way to exercise the *download*
 * half rather than stopping at a connection refusal. Bodies differ per id
 * precisely so a crossed stream shows up as the wrong contents rather than as
 * a passing test.
 */
private class TinyImageServer {
    private val socket = ServerSocket(0)

    init {
        thread(isDaemon = true) {
            while (!socket.isClosed) {
                try {
                    serveOne()
                } catch (_: Exception) {
                    return@thread // closed, or the test is over
                }
            }
        }
    }

    /** The body served for [id] — distinct, and long enough to be worth racing. */
    fun body(id: String): String = "pixels-$id".repeat(512)

    fun urlFor(id: String): String = "http://127.0.0.1:${socket.localPort}/$id.jpg"

    fun close() = socket.close()

    private fun serveOne() {
        val client = socket.accept()
        thread(isDaemon = true) {
            client.use {
                val reader = it.getInputStream().bufferedReader()
                val requestLine = reader.readLine() ?: return@use
                val id = requestLine.split(' ')[1].removePrefix("/").removeSuffix(".jpg")
                val payload = body(id)
                it.getOutputStream().writer().apply {
                    write("HTTP/1.1 200 OK\r\n")
                    write("Content-Length: ${payload.toByteArray().size}\r\n")
                    write("Connection: close\r\n\r\n")
                    write(payload)
                    flush()
                }
            }
        }
    }
}
