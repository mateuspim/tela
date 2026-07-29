package cc.pym.tela

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * tela's one Flutter engine, held by the process rather than by a screen.
 *
 * **This is what lets the download queue outlive the app being closed.** The
 * drain is Dart — `DrainDownloadQueue` over a Drift table, with the tier
 * resolution, the pin, the history withholding and two NSFW invariants around
 * each entry — so it runs for exactly as long as an engine is alive to run it.
 * An engine owned by [MainActivity] dies when the activity does, which is why
 * [DownloadQueueService] used to take its own notification down on a swipe out
 * of recents: an anchor over a queue that had stopped moving would be a lie the
 * user could not dismiss. Cached here, the engine survives the activity, the
 * drain keeps going, and the anchor tells the truth.
 *
 * **Created on the first launch, not pre-warmed in `Application.onCreate`.**
 * Building it eagerly moves engine startup ahead of everything the system does
 * for a cold start, and cold start has bitten this project before (see the
 * release cold-launch hang in HANDOFF.md). [ensure] is called from the
 * activity's own `onCreate`, which is the moment the engine would have been
 * built anyway — the difference is only that the next activity reuses it.
 *
 * ```kotlin
 * override fun getCachedEngineId(): String = TelaEngine.ensure(applicationContext)
 * ```
 */
object TelaEngine {
    /** The cache key. One engine, so one id. */
    const val ID: String = "tela"

    /**
     * The application-scoped channels — the ones a download needs when there is
     * no screen left to have asked for it. Null until [ensure] has run.
     *
     * Handed out so [MainActivity] can lend and withdraw the activity the two
     * storage prompts need; everything else on it works without one.
     */
    var imageStore: ImageStoreChannel? = null
        private set

    /**
     * Answers the cache id, building and caching the engine the first time.
     *
     * Idempotent: every launch calls it, and only the first one creates
     * anything. [context] should be the application context — the engine
     * outlives any activity by design, and holding one here is the leak this
     * whole file exists to avoid.
     */
    fun ensure(context: Context): String {
        val cache = FlutterEngineCache.getInstance()
        if (cache.get(ID) == null) cache.put(ID, create(context.applicationContext))
        return ID
    }

    /**
     * Builds the engine, starts Dart on it, and wires the channels that must
     * answer with no activity attached.
     *
     * Dart is started here rather than left to the fragment: a cached engine is
     * handed to `FlutterFragment.withCachedEngine`, which expects one that is
     * already running.
     */
    private fun create(context: Context): FlutterEngine {
        val engine = FlutterEngine(context)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        imageStore = ImageStoreChannel(context).apply { attachTo(engine) }
        DownloadQueueChannel(context).attachTo(engine)
        return engine
    }
}
