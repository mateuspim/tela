package cc.pym.tela

import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService

/**
 * Hard-deleting a download, in the one place that knows the gallery tier is
 * different.
 *
 * Split out of [ImageStoreChannel] because one tier here behaves unlike the other
 * two: from API 30 a `sharedGallery` file goes only through
 * `MediaStore.createDeleteRequest`, which is the OS's own confirmation dialog and
 * so needs a screen, while appPrivate and the SAF document delete through a
 * Context and ask nobody. Everything that follows from that asymmetry — the
 * stale-row rule that once killed the process, batching twenty deletes into one
 * prompt, and what to answer when there is no screen to prompt on — lives here
 * rather than being spread through the router.
 *
 * [prompts] is read through a lambda, not held: the activity that serves it comes
 * and goes, and a batch that outlived it must see the current answer, not the one
 * that was true when this was built.
 *
 * ```kotlin
 * DownloadDeleting(context, executor, ::post) { prompts }.deleteBatch(call, result)
 * ```
 */
internal class DownloadDeleting(
    private val context: Context,
    private val storageExecutor: ExecutorService,
    private val onMainThread: (() -> Unit) -> Unit,
    private val prompts: () -> StoragePrompts?,
) {
    /**
     * Hard-deletes a downloaded file, routing the gallery tier by API level.
     *
     * appPrivate and the SAF document delete synchronously off the UI thread.
     * The gallery tier on API 30+ cannot: `MediaStore.createDeleteRequest`
     * shows the OS's own confirmation and returns through an activity result, so
     * it is launched like the folder grant. On API 29 a direct delete works, so
     * it stays on the storage thread with the other two.
     */
    fun deleteOne(call: MethodCall, result: MethodChannel.Result) {
        val tier = call.argument<String>("tier")
        val location = call.argument<String>("location")
        if (tier == null || location == null) {
            result.success(imageStoreFailure("unavailable"))
            return
        }
        val uri = Uri.parse(location)
        if (tier == "sharedGallery" && systemConfirmsGalleryDelete()) {
            confirmGalleryDeletion(uri, result)
            return
        }
        onStorageThread(result) { ImageStorage(context).deleteDownload(tier, uri) }
    }

    /**
     * Asks the OS to delete one gallery image — unless its row is already gone.
     *
     * Off the UI thread for the MediaStore query, then back onto it because only
     * an Activity can launch the confirmation. Same stale-row rule as
     * [planDeletions], which is where it is explained.
     */
    private fun confirmGalleryDeletion(uri: Uri, result: MethodChannel.Result) {
        storageExecutor.execute {
            val live = ImageStorage(context).galleryRowExists(uri)
            onMainThread {
                if (live) {
                    requestGalleryDeletions(listOf(uri), emptyList(), result)
                } else {
                    result.success(deletionOutcome(listOf(uri.toString())))
                }
            }
        }
    }

    /**
     * Hard-deletes a whole selection, batching the gallery tier into one prompt.
     *
     * The files and SAF documents delete on the storage thread; the gallery
     * items (on API 30+) are gathered and handed to a single
     * `createDeleteRequest`, so a selection of twenty gallery downloads is one
     * OS prompt rather than twenty. The already-deleted locations are carried
     * into that prompt so the final answer is the whole batch's outcome.
     */
    fun deleteBatch(call: MethodCall, result: MethodChannel.Result) {
        val items = readDeletionItems(call) ?: run {
            result.success(imageStoreFailure("unavailable"))
            return
        }
        storageExecutor.execute {
            val plan = planDeletions(ImageStorage(context), items)
            onMainThread {
                if (plan.confirm.isEmpty()) {
                    result.success(deletionOutcome(plan.deleted))
                } else {
                    requestGalleryDeletions(plan.confirm, plan.deleted, result)
                }
            }
        }
    }

    /**
     * Launches one system confirmation for every gallery delete in the batch.
     *
     * [alreadyDeleted] are the non-gallery files already removed, kept in the
     * answer either way — including when there is no screen to ask on, which is
     * an ordinary state now that the queue drains without one. A gallery delete
     * simply cannot happen then: the OS owns that prompt, and Dart is told the
     * truth about what went.
     */
    @RequiresApi(Build.VERSION_CODES.R)
    private fun requestGalleryDeletions(
        galleryUris: List<Uri>,
        alreadyDeleted: List<String>,
        result: MethodChannel.Result,
    ) {
        // Guarded because `createDeleteRequest` is the call that actually threw
        // (a stale row, which [planDeletions] now filters out) and an uncaught
        // throw here is on the main thread — it kills the app. The launch is
        // guarded too, inside [StoragePrompts.askDeleteConfirmation], which is
        // where it now lives.
        val request = try {
            MediaStore.createDeleteRequest(context.contentResolver, galleryUris)
        } catch (_: Exception) {
            result.success(deletionOutcome(alreadyDeleted))
            return
        }
        val asked = prompts()?.askDeleteConfirmation(request.intentSender) { accepted ->
            val locations = if (accepted) galleryUris.map(Uri::toString) else emptyList()
            result.success(deletionOutcome(alreadyDeleted + locations))
        }
        if (asked != true) result.success(imageStoreFailure("unavailable"))
    }

    /** Runs a delete off the UI thread, answering on it. */
    private fun onStorageThread(
        result: MethodChannel.Result,
        work: () -> Map<String, Any>,
    ) = answerOffThread(storageExecutor, onMainThread, result, work)
}
