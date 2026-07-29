package cc.pym.tela

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Raises and lowers the download queue's foreground anchor.
 *
 * Application-scoped, like the drain it speaks for: the queue announces its own
 * count from Dart with no widget and no frame involved, so the call can arrive
 * long after the last screen closed. An activity-owned handler would be holding
 * a destroyed activity by then — see [ImageStoreChannel] for the same argument
 * at more length.
 *
 * The notification's words are Dart's. Every user-facing string in tela comes
 * from the ARB (CLAUDE.md), and one composed in Kotlin would be the single
 * surface that stayed English when a locale was added.
 *
 * ```kotlin
 * DownloadQueueChannel(applicationContext).attachTo(engine)
 * ```
 */
class DownloadQueueChannel(context: Context) {
    private val context: Context = context.applicationContext

    /** Answers `cc.pym.tela/download_queue` on [engine] for as long as it lives. */
    fun attachTo(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "anchor" -> result.success(
                DownloadQueueService.anchor(
                    context,
                    call.argument<String>("title").orEmpty(),
                    call.argument<String>("body").orEmpty(),
                ),
            )
            "release" -> {
                DownloadQueueService.release(context)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private companion object {
        const val CHANNEL = "cc.pym.tela/download_queue"
    }
}
