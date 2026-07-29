package cc.pym.tela

import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The two storage steps that cannot happen without a screen: the folder picker
 * and the OS's own delete confirmation.
 *
 * Both are `startActivityForResult` in disguise, so an Activity has to launch
 * them and hear the answer. Everything else [ImageStoreChannel] does needs only
 * a Context, which is why the split is here and not one class further out.
 *
 * Each answers **false when it could not ask** — no activity attached, or one
 * prompt already in flight. That is not an error to report to the user: a
 * download draining behind a closed app has nobody to ask, and it says so.
 */
interface StoragePrompts {
    /**
     * Opens the SAF folder picker with [intent], answering the granted tree and
     * the flags it came with, or null for a cancelled pick.
     */
    fun askFolderGrant(intent: Intent, onAnswer: (Uri?, Int) -> Unit): Boolean

    /**
     * Shows the system delete confirmation [request] covers, answering whether
     * the user accepted it.
     */
    fun askDeleteConfirmation(request: IntentSender, onAnswer: (Boolean) -> Unit): Boolean
}

/**
 * Every storage call Dart makes: downloads, tier moves, listings, probes and
 * deletes.
 *
 * **Owned by the process, not by a screen, and that is the point.** The download
 * queue keeps draining while tela is backgrounded and — with the engine cached
 * in [TelaEngine] — after the activity is gone entirely. A handler bound to
 * `MainActivity` would still be answering those calls through a destroyed
 * activity, holding its whole view hierarchy alive for the length of a batch:
 * precisely the memory a foreground service is asking the OS not to reclaim.
 *
 * The two steps that genuinely need a screen go out through [prompts], which
 * [MainActivity] lends while it is attached and withdraws when it is not.
 *
 * ```kotlin
 * ImageStoreChannel(applicationContext).apply { attachTo(engine) }
 * ```
 */
class ImageStoreChannel(context: Context) {
    private val context: Context = context.applicationContext

    /**
     * Listing, deleting and preview caching, in the order they were asked for.
     *
     * Serial on purpose: none of these have a reason to overlap, and their
     * ordering is free correctness a pool would give away for nothing. Downloads
     * do *not* run here — they go to [Downloads.executor], because streaming an
     * image before writing it made every download in a batch wait for the one in
     * front of it.
     *
     * Never shut down. It used to stop with `MainActivity.onDestroy`, which is
     * exactly wrong for work that outlives the screen; one idle thread is what
     * the process pays for that.
     */
    private val storageExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    private val mainThread = Handler(Looper.getMainLooper())

    /**
     * The attached screen, or null when there is none.
     *
     * Set by [MainActivity] on attach and cleared on detach, so a prompt is
     * never launched into an activity the system has already destroyed.
     */
    var prompts: StoragePrompts? = null

    /** Answers `cc.pym.tela/images` on [engine] for as long as it lives. */
    fun attachTo(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::handle)
    }

    /**
     * Routes one call. Internal rather than private so the Kotlin suite can
     * drive it directly: a [FlutterEngine] cannot be built under Robolectric,
     * and the behaviour worth pinning here — what these answer with no screen
     * attached — is on this side of the channel, not in the crossing.
     */
    internal fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "storeImage" -> handleStoreImage(call, result)
            "copyStoredImage" -> handleCopyStoredImage(call, result)
            "listPrivateImages" -> onStorageThread(result) { ImageStorage(context).listPrivate() }
            "deleteDownload" -> handleDeleteDownload(call, result)
            "deleteDownloads" -> handleDeleteDownloads(call, result)
            "galleryDeleteConfirmedBySystem" ->
                result.success(mapOf("confirmed" to systemConfirmsGalleryDelete()))
            "canReadImage" -> handleCanReadImage(call, result)
            "canReadImages" -> handleCanReadImages(call, result)
            "materializeImage" -> handleMaterializeImage(call, result)
            "releasePreview" -> handleReleasePreview(call, result)
            "describeDownloadLocation" -> describeDownloadLocation(result)
            "chooseDownloadFolder" -> handleChooseDownloadFolder(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleStoreImage(call: MethodCall, result: MethodChannel.Result) {
        val request = imageStoreRequest(call) ?: run {
            result.success(imageStoreFailure("unavailable"))
            return
        }
        // A files-outside-gallery download needs a folder first, but the
        // device/card choice is a Flutter screen, not a native picker: answer
        // notConfigured so Dart can run the chooser and retry. Opening a blank
        // tree browser here — the old behaviour — is exactly the UX slice 2
        // replaced.
        if (request.tier == "filesOutsideGallery") {
            outsideGalleryProblem()?.let { problem ->
                result.success(imageStoreFailure(problem))
                return
            }
        }
        storeImage(request, result)
    }

    /**
     * Downloads on [Downloads.executor], never on [storageExecutor].
     *
     * This one routing line is what makes a batch faster: the store streams the
     * image before it writes, so on the serial executor every download in a
     * queue waited for the one in front of it however many Dart ran at once.
     */
    private fun storeImage(request: ImageStoreRequest, result: MethodChannel.Result) {
        val storage = ImageStorage(context)
        val folder = outsideGalleryTree()
        Downloads.executor.execute {
            val response = storage.store(request, folder)
            onMainThread { result.success(response) }
        }
    }

    /**
     * Copies a file already on this device into another tier.
     *
     * The same files-outside-gallery pre-check [handleStoreImage] applies: a
     * move into that tier needs a granted folder, and answering notConfigured
     * lets Dart run its own chooser rather than opening a blank tree browser.
     */
    private fun handleCopyStoredImage(call: MethodCall, result: MethodChannel.Result) {
        val request = imageCopyRequest(call) ?: run {
            result.success(imageStoreFailure("unavailable"))
            return
        }
        if (request.tier == "filesOutsideGallery") {
            outsideGalleryProblem()?.let { problem ->
                result.success(imageStoreFailure(problem))
                return
            }
        }
        // On [Downloads.executor] for the same reason a download is: this is
        // bulk file I/O, and a selection of thirty would otherwise queue behind
        // the serial storage thread that listing and deleting share.
        val storage = ImageStorage(context)
        val folder = outsideGalleryTree()
        Downloads.executor.execute {
            val response = storage.copy(request, folder)
            onMainThread { result.success(response) }
        }
    }

    /**
     * Probes a whole history's worth of files in one crossing.
     *
     * The download history asks about **every** row it shows, and one call per
     * row meant hundreds of method-channel round trips all queueing behind each
     * other on the serial [storageExecutor] — the badges took long enough to
     * arrive that the screen looked broken (owner, 2026-07-28). The probes
     * themselves are unchanged; what goes away is the traffic.
     *
     * On [Downloads.executor], not [storageExecutor]: this is bulk read-only
     * I/O with no ordering to preserve, and leaving it on the serial thread
     * would make a long probe block the delete or listing the user is waiting
     * on. Each file is opened exactly as the single probe opens it, because
     * only opening it answers the question honestly.
     */
    private fun handleCanReadImages(call: MethodCall, result: MethodChannel.Result) {
        val locations = call.argument<List<String>>("locations") ?: run {
            result.success(mapOf("success" to true, "readable" to emptyList<Boolean>()))
            return
        }
        val storage = ImageStorage(context)
        Downloads.executor.execute {
            val readable = locations.map { location ->
                try {
                    storage.canRead(Uri.parse(location))["readable"] == true
                } catch (_: Exception) {
                    false
                }
            }
            onMainThread { result.success(mapOf("success" to true, "readable" to readable)) }
        }
    }

    private fun handleCanReadImage(call: MethodCall, result: MethodChannel.Result) {
        val location = call.argument<String>("location") ?: run {
            result.success(mapOf("success" to true, "readable" to false))
            return
        }
        onStorageThread(result) { ImageStorage(context).canRead(Uri.parse(location)) }
    }

    private fun handleMaterializeImage(call: MethodCall, result: MethodChannel.Result) {
        val location = call.argument<String>("location") ?: run {
            result.success(mapOf("success" to false))
            return
        }
        onStorageThread(result) { ImageStorage(context).materialise(Uri.parse(location)) }
    }

    private fun handleReleasePreview(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path") ?: run {
            result.success(mapOf("success" to true))
            return
        }
        onStorageThread(result) { ImageStorage(context).releasePreview(path) }
    }

    /**
     * Hard-deletes a downloaded file, routing the gallery tier by API level.
     *
     * appPrivate and the SAF document delete synchronously off the UI thread.
     * The gallery tier on API 30+ cannot: `MediaStore.createDeleteRequest`
     * shows the OS's own confirmation and returns through an activity result, so
     * it is launched like the folder grant. On API 29 a direct delete works, so
     * it stays on the storage thread with the other two.
     */
    private fun handleDeleteDownload(call: MethodCall, result: MethodChannel.Result) {
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
    private fun handleDeleteDownloads(call: MethodCall, result: MethodChannel.Result) {
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
        val asked = prompts?.askDeleteConfirmation(request.intentSender) { accepted ->
            val locations = if (accepted) galleryUris.map(Uri::toString) else emptyList()
            result.success(deletionOutcome(alreadyDeleted + locations))
        }
        if (asked != true) result.success(imageStoreFailure("unavailable"))
    }

    /**
     * What a delete batch resolved to before any prompt: the gallery rows the OS
     * must confirm, and the locations that are already gone.
     */
    private data class DeletionPlan(val confirm: List<Uri>, val deleted: List<String>)

    /**
     * Deletes what tela can delete itself, and sorts the rest into live gallery
     * rows and stale ones.
     *
     * **A gallery row whose MediaStore row no longer exists counts as deleted**,
     * because it is: the end state the user asked for is already true. Handing it
     * to `MediaStore.createDeleteRequest` instead throws `IllegalArgumentException`
     * on the main thread and kills the process — and since the history is where
     * those rows live and *clearing the history is the only gesture that removes
     * them*, every retry died before trimming anything and the user could not
     * escape without wiping app data (owner, 2026-07-28).
     *
     * It needs no mistake of ours to happen: a `sharedGallery` row outlives its
     * file whenever the file goes away behind tela's back — deleted from Photos,
     * from a file manager, by a storage cleaner, or on a card that was unmounted.
     * Rendering already tolerates that; it is what the missing badge shows.
     */
    private fun planDeletions(
        storage: ImageStorage,
        items: List<Pair<String, Uri>>,
    ): DeletionPlan {
        val gallery = mutableListOf<Uri>()
        val deleted = mutableListOf<String>()
        for ((tier, uri) in items) {
            if (tier == "sharedGallery" && systemConfirmsGalleryDelete()) {
                gallery.add(uri)
            } else if (storage.deleteDownload(tier, uri)["success"] == true) {
                deleted.add(uri.toString())
            }
        }
        val (live, stale) = gallery.partition { storage.galleryRowExists(it) }
        return DeletionPlan(live, deleted + stale.map(Uri::toString))
    }

    private fun readDeletionItems(call: MethodCall): List<Pair<String, Uri>>? {
        val raw = call.argument<List<Map<String, String>>>("items") ?: return null
        return raw.mapNotNull { item ->
            val tier = item["tier"]
            val location = item["location"]
            if (tier == null || location == null) null else tier to Uri.parse(location)
        }
    }

    /** True on API 30+, where every gallery delete goes through the OS prompt. */
    private fun systemConfirmsGalleryDelete(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

    /**
     * A delete batch's answer: what went, whether or not everything did.
     *
     * Always a success, because "some of these were already gone" and "the user
     * declined the prompt" are outcomes, not failures — Dart forgets exactly the
     * rows named here and leaves the others alone.
     */
    private fun deletionOutcome(deleted: List<String>): Map<String, Any> =
        mapOf("success" to true, "deleted" to deleted)

    /**
     * Opens the folder picker pointed at the chosen volume, no download waiting.
     *
     * The `kind` ("device" or "sdCard") pre-aims the picker so the user confirms
     * one folder instead of hunting through a blank tree browser — the whole
     * point of the device/card choice. A card asked for while the slot is empty
     * has no volume to aim at, so it answers `notConfigured` rather than opening
     * a picker that could land anywhere. So does a call with no screen attached:
     * a picker needs one, and Dart only ever asks for this from a screen.
     *
     * The persistable-grant flags are added here so no caller can forget them.
     */
    private fun handleChooseDownloadFolder(call: MethodCall, result: MethodChannel.Result) {
        val kind = call.argument<String>("kind") ?: run {
            result.success(imageStoreFailure("unavailable"))
            return
        }
        val intent = DownloadVolumes(context).openTreeIntentFor(kind) ?: run {
            result.success(imageStoreFailure("notConfigured"))
            return
        }
        val asked = prompts?.askFolderGrant(intent.addFlags(DIRECTORY_ACCESS_FLAGS)) { tree, flags ->
            onFolderGrant(tree, flags, result)
        }
        if (asked != true) result.success(imageStoreFailure("notConfigured"))
    }

    private fun onFolderGrant(tree: Uri?, flags: Int, result: MethodChannel.Result) {
        if (tree == null || !saveOutsideGalleryTree(tree, flags)) {
            result.success(imageStoreFailure("notConfigured"))
            return
        }
        // The only caller is the device/card chooser, so answer with the
        // location the grant produced; the screen redraws without a second round
        // trip, and the Dart coordinator retries the download it stands in for.
        describeDownloadLocation(result)
    }

    /**
     * Persists the granted tree, refusing one that would shadow the gallery.
     *
     * [ImageStorage] refuses it again at write time and that is the gate that
     * matters; this one only makes the user find out at the picker, where they
     * can pick another folder, instead of at the first download. `Pictures` is
     * the obvious thing to grant and it is the one that must not be taken — see
     * [TreeLocation.overlapsGallery].
     */
    private fun saveOutsideGalleryTree(tree: Uri, returnedFlags: Int): Boolean {
        if (tree.authority != EXTERNAL_STORAGE_PROVIDER) return false
        if (TreeLocation.of(tree)?.overlapsGallery != false) return false
        val grantedFlags = returnedFlags and PERSISTED_DIRECTORY_ACCESS_FLAGS
        return try {
            context.contentResolver.takePersistableUriPermission(tree, grantedFlags)
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .edit()
                .putString(OUTSIDE_GALLERY_TREE, tree.toString())
                .apply()
            true
        } catch (_: SecurityException) {
            false
        }
    }

    /** Describes the location off the UI thread; it does filesystem stats. */
    private fun describeDownloadLocation(result: MethodChannel.Result) {
        onStorageThread(result) {
            DownloadFolderDescribing(context).describe(outsideGalleryTree())
        }
    }

    /**
     * Why the files-outside-gallery folder can't take a download, or null when
     * it can. `notConfigured` when nothing was ever chosen — Dart runs the
     * chooser and retries. `folderUnavailable` when a folder is set but its
     * volume is gone, an ejected card: nothing is rerouted, and the toast says
     * "reconnect it" rather than offering setup for a folder that already
     * exists.
     */
    private fun outsideGalleryProblem(): String? {
        val tree = outsideGalleryTree() ?: return "notConfigured"
        return if (DownloadFolderDescribing(context).isAvailable(tree)) null else "folderUnavailable"
    }

    private fun outsideGalleryTree(): String? {
        return context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getString(OUTSIDE_GALLERY_TREE, null)
    }

    private fun imageCopyRequest(call: MethodCall): ImageCopyRequest? {
        val source = call.argument<String>("source") ?: return null
        val id = call.argument<String>("id") ?: return null
        val from = call.argument<String>("from") ?: return null
        val purity = call.argument<String>("purity") ?: return null
        val tier = call.argument<String>("tier") ?: return null
        return ImageCopyRequest(source, id, from, purity, tier)
    }

    private fun imageStoreRequest(call: MethodCall): ImageStoreRequest? {
        val source = call.argument<String>("source") ?: return null
        val id = call.argument<String>("id") ?: return null
        val imageUrl = call.argument<String>("imageUrl") ?: return null
        val purity = call.argument<String>("purity") ?: return null
        val tier = call.argument<String>("tier") ?: return null
        return ImageStoreRequest(source, id, imageUrl, purity, tier)
    }

    /** Runs filesystem work off the UI thread, answering on it. */
    private fun onStorageThread(
        result: MethodChannel.Result,
        work: () -> Map<String, Any>,
    ) {
        storageExecutor.execute {
            val response = try {
                work()
            } catch (_: Exception) {
                imageStoreFailure("unavailable")
            }
            onMainThread { result.success(response) }
        }
    }

    /**
     * Posts back to the main thread without going through an activity.
     *
     * `runOnUiThread` is an Activity method and silently does nothing useful
     * once the activity is gone — which is precisely the window a download
     * anchored by [DownloadQueueService] runs in. A method-channel reply must
     * be delivered on the main thread whether or not a screen is still there
     * to have asked for it.
     */
    private fun onMainThread(reply: () -> Unit) = mainThread.post(reply)

    private fun imageStoreFailure(code: String): Map<String, Any> = mapOf(
        "success" to false,
        "errorCode" to code,
    )

    private companion object {
        const val CHANNEL = "cc.pym.tela/images"
        const val PREFERENCES = "tela.storage"
        const val OUTSIDE_GALLERY_TREE = "outsideGalleryTree"
        const val EXTERNAL_STORAGE_PROVIDER = "com.android.externalstorage.documents"
        const val DIRECTORY_ACCESS_FLAGS =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
        const val PERSISTED_DIRECTORY_ACCESS_FLAGS =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
    }
}
