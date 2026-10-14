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

    /**
     * The one storage call that needs a screen, and everything that follows from
     * that. It reads [prompts] through a lambda rather than being handed the
     * value, so a batch running past a detach sees the withdrawal.
     */
    private val deleting = DownloadDeleting(
        this.context,
        storageExecutor,
        ::onMainThread,
    ) { prompts }

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
            "retagStoredImage" -> handleRetagStoredImage(call, result)
            "listPrivateImages" -> handleListPrivateImages(result)
            "listAppPrivateImages" ->
                onStorageThread(result) { ImageStorage(context).listAppPrivate() }
            "deleteDownload" -> deleting.deleteOne(call, result)
            "deleteDownloads" -> deleting.deleteBatch(call, result)
            "galleryDeleteConfirmedBySystem" ->
                result.success(mapOf("confirmed" to systemConfirmsGalleryDelete()))
            "canReadImage" -> handleCanReadImage(call, result)
            "canReadImages" -> handleCanReadImages(call, result)
            "measureImages" -> handleMeasureImages(call, result)
            "inspectImages" -> handleInspectImages(call, result)
            "materializeImage" -> handleMaterializeImage(call, result)
            "materializeRemoteImage" -> handleMaterializeRemoteImage(call, result)
            "materializeVaultThumbnail" -> handleMaterializeVaultThumbnail(call, result)
            "releasePreview" -> handleReleasePreview(call, result)
            "describeDownloadLocation" -> describeDownloadLocation(result)
            "chooseDownloadFolder" -> handleChooseDownloadFolder(call, result)
            "setVaultFolder" -> handleSetVaultFolder(call, result)
            else -> result.notImplemented()
        }
    }

    /**
     * Lists both homes of the private library.
     *
     * The target is read on the calling thread and handed over, not read inside
     * the worker: [outsideGalleryTarget] touches SharedPreferences, and the
     * point of [onStorageThread] is the file walk that follows it.
     */
    private fun handleListPrivateImages(result: MethodChannel.Result) {
        val target = outsideGalleryTarget()
        onStorageThread(result) { ImageStorage(context).listPrivate(target) }
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
        val target = outsideGalleryTarget()
        Downloads.executor.execute {
            val response = storage.store(request, target)
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
        val target = outsideGalleryTarget()
        Downloads.executor.execute {
            val response = storage.copy(request, target)
            onMainThread { result.success(response) }
        }
    }

    /**
     * Moves a stored image between tag folders inside its own tier.
     *
     * On [Downloads.executor] like the copy it exists to avoid: a retag of a
     * whole selection is bulk work, and the serial [storageExecutor] is where
     * the listing and the delete the user is waiting on already queue.
     *
     * `tag` is optional here in a way `tier` and `location` are not — its
     * absence means the tier root, which is a real destination.
     */
    private fun handleRetagStoredImage(call: MethodCall, result: MethodChannel.Result) {
        val tier = call.argument<String>("tier")
        val location = call.argument<String>("location")
        if (tier == null || location == null) {
            result.success(imageStoreFailure("unavailable"))
            return
        }
        val tag = call.argument<String>("tag")
        val storage = ImageStorage(context)
        val folder = outsideGalleryTree()
        Downloads.executor.execute {
            val response = storage.retag(tier, Uri.parse(location), tag, folder)
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

    /**
     * Judges each of `locations` whole, empty, cut off or unreadable, in order.
     *
     * One crossing for the whole library, on [Downloads.executor] like
     * [handleMeasureImages]: a per-file round trip over thousands of images is
     * the stall the bulk delete already learned about. See
     * [StoredImageInspecting].
     */
    private fun handleInspectImages(call: MethodCall, result: MethodChannel.Result) {
        val locations = call.argument<List<String>>("locations") ?: run {
            result.success(mapOf("conditions" to emptyList<String>()))
            return
        }
        val inspecting = StoredImageInspecting(context)
        Downloads.executor.execute {
            val conditions = locations.map { inspecting.inspect(Uri.parse(it)) }
            onMainThread { result.success(mapOf("conditions" to conditions)) }
        }
    }

    /**
     * Sizes a whole listing in one crossing, on [Downloads.executor].
     *
     * Same shape and the same reasoning as [handleCanReadImages]: the offload
     * screen measures every recorded download, and one round trip per row is
     * what made the missing badges look broken in 2026-07-28. Bulk read-only
     * I/O with no ordering to preserve, so it stays off the serial thread.
     *
     * A location that cannot be measured contributes a zero rather than an
     * error. The tally is a promise about space, and one unreadable file must
     * not cost the user every other number in the batch.
     */
    private fun handleMeasureImages(call: MethodCall, result: MethodChannel.Result) {
        val locations = call.argument<List<String>>("locations") ?: run {
            result.success(emptyAnswer())
            return
        }
        val storage = ImageStorage(context)
        Downloads.executor.execute {
            val measured = locations.map { location ->
                try {
                    storage.measure(Uri.parse(location))
                } catch (_: Exception) {
                    mapOf<String, Any>("bytes" to 0L, "removable" to false)
                }
            }
            onMainThread {
                result.success(
                    mapOf(
                        "success" to true,
                        "bytes" to measured.map { it["bytes"] as Long },
                        "removable" to measured.map { it["removable"] as Boolean },
                    ),
                )
            }
        }
    }

    private fun emptyAnswer(): Map<String, Any> = mapOf(
        "success" to true,
        "bytes" to emptyList<Long>(),
        "removable" to emptyList<Boolean>(),
    )

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

    /**
     * Fetches a wallpaper nobody has downloaded, so a beam can still send it.
     *
     * On the *download* executor rather than the storage one: this is a network
     * fetch of many megabytes, and queueing it behind the serial storage thread
     * would stall every listing and badge probe while it ran.
     */
    private fun handleMaterializeRemoteImage(call: MethodCall, result: MethodChannel.Result) {
        val imageUrl = call.argument<String>("imageUrl") ?: run {
            result.success(mapOf("success" to false))
            return
        }
        Downloads.executor.execute {
            val response = ImageStorage(context).materialiseRemote(imageUrl)
            onMainThread { result.success(response) }
        }
    }

    private fun handleMaterializeVaultThumbnail(call: MethodCall, result: MethodChannel.Result) {
        val location = call.argument<String>("location") ?: run {
            result.success(mapOf("success" to false))
            return
        }
        val maxDimensionPx = call.argument<String>("maxDimensionPx")?.toIntOrNull()
            ?: DEFAULT_THUMBNAIL_MAX_DIMENSION_PX
        onStorageThread(result) {
            ImageStorage(context).materialiseThumbnail(Uri.parse(location), maxDimensionPx)
        }
    }

    private fun handleReleasePreview(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path") ?: run {
            result.success(mapOf("success" to true))
            return
        }
        onStorageThread(result) { ImageStorage(context).releasePreview(path) }
    }

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
            DownloadFolderDescribing(context).describe(outsideGalleryTree()) +
                mapOf("vaultLabel" to vaultLabel())
        }
    }

    /**
     * Renames the hidden folder explicit images go to, from now on.
     *
     * **Renames nothing on disk**, and the settings row says so: the old
     * directory keeps whatever is in it, and the app keeps listing both — see
     * [SafVaultListing]. Moving a folder full of images because a text field
     * lost focus is not a rename, it is a migration, and a failed one would
     * strand the library in two places with no record of which half went where.
     *
     * Refuses a label that could not be a directory, answering false rather than
     * repairing it: the caller has a field to mark invalid, and a silently
     * corrected name is a folder the user did not choose.
     */
    private fun handleSetVaultFolder(call: MethodCall, result: MethodChannel.Result) {
        val label = call.argument<String>("label")
        if (label == null || !VaultFolders.isValidLabel(label)) {
            result.success(mapOf("success" to false))
            return
        }
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(VAULT_LABEL, label)
            .apply()
        result.success(mapOf("success" to true, "vaultLabel" to label))
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

    private fun outsideGalleryTree(): String? = StorageTargetStore.tree(context)

    /**
     * The vault label, falling back to the default for a missing **or unusable**
     * one.
     *
     * The second half matters: a preferences file is editable on a rooted device
     * and survives a downgrade, so the value read here is not necessarily one
     * [handleSetVaultFolder] wrote. Falling back rather than failing keeps a
     * bad row from making explicit downloads impossible, and the allowlist is
     * applied again in [VaultFolders.directoryOf] before it becomes a path.
     */
    private fun vaultLabel(): String = StorageTargetStore.vaultLabel(context)

    /** Where the files tier writes right now: the granted tree and the vault. */
    private fun outsideGalleryTarget(): OutsideGalleryTarget =
        OutsideGalleryTarget(outsideGalleryTree(), vaultLabel())

    private fun imageCopyRequest(call: MethodCall): ImageCopyRequest? {
        val source = call.argument<String>("source") ?: return null
        val id = call.argument<String>("id") ?: return null
        val from = call.argument<String>("from") ?: return null
        val purity = call.argument<String>("purity") ?: return null
        val tier = call.argument<String>("tier") ?: return null
        return ImageCopyRequest(source, id, from, purity, tier, call.argument<String>("tag"))
    }

    private fun imageStoreRequest(call: MethodCall): ImageStoreRequest? {
        val source = call.argument<String>("source") ?: return null
        val id = call.argument<String>("id") ?: return null
        val imageUrl = call.argument<String>("imageUrl") ?: return null
        val purity = call.argument<String>("purity") ?: return null
        val tier = call.argument<String>("tier") ?: return null
        return ImageStoreRequest(source, id, imageUrl, purity, tier, call.argument<String>("tag"))
    }

    /** Runs filesystem work off the UI thread, answering on it. */
    private fun onStorageThread(
        result: MethodChannel.Result,
        work: () -> Map<String, Any>,
    ) = answerOffThread(storageExecutor, ::onMainThread, result, work)

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

    private companion object {
        const val CHANNEL = "cc.pym.tela/images"
        const val PREFERENCES = "tela.storage"
        const val OUTSIDE_GALLERY_TREE = "outsideGalleryTree"
        const val VAULT_LABEL = "vaultLabel"
        const val EXTERNAL_STORAGE_PROVIDER = "com.android.externalstorage.documents"
        const val DIRECTORY_ACCESS_FLAGS =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
        const val PERSISTED_DIRECTORY_ACCESS_FLAGS =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION

        /** Used only if Dart's own tile-width argument is somehow missing. */
        const val DEFAULT_THUMBNAIL_MAX_DIMENSION_PX = 200
    }
}

/**
 * The failure shape every image-store method answers with.
 *
 * Top-level because [DownloadDeleting] speaks the same contract and Dart's
 * `MethodChannelImageStore` reads exactly these two keys; two definitions of it
 * is how they would drift.
 */
internal fun imageStoreFailure(code: String): Map<String, Any> = mapOf(
    "success" to false,
    "errorCode" to code,
)

/**
 * Runs storage work on [executor] and answers [result] on the main thread, with
 * an unexpected throw becoming `unavailable` rather than a dropped reply.
 *
 * Shared for the same reason as [imageStoreFailure]: the delete path needs the
 * identical guarantee, and a Dart future that never completes is the one failure
 * mode nothing above can recover from.
 */
internal fun answerOffThread(
    executor: ExecutorService,
    onMainThread: (() -> Unit) -> Unit,
    result: MethodChannel.Result,
    work: () -> Map<String, Any>,
) {
    executor.execute {
        val response = try {
            work()
        } catch (_: Exception) {
            imageStoreFailure("unavailable")
        }
        onMainThread { result.success(response) }
    }
}
