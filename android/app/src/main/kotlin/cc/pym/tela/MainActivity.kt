package cc.pym.tela

import android.content.Intent
import android.graphics.Rect
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.app.WallpaperManager
import android.view.WindowManager
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * A FragmentActivity, not a plain FlutterActivity: local_auth's BiometricPrompt
 * needs a FragmentManager, and a plain FlutterActivity fails at prompt time
 * rather than at build time — so the app-lock would compile and then not work.
 */
class MainActivity : FlutterFragmentActivity() {
    private val wallpaperExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val imageStoreExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val shareExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    /**
     * Downloads, and **only** downloads. Separate from [imageStoreExecutor],
     * and the reason the download queue is faster rather than merely tidier.
     *
     * `ImageStorage.store` streams the image over HTTP before it writes, so on
     * a single-thread executor every download in a batch waits for the one in
     * front of it — Dart-side concurrency bought nothing, because all of it
     * queued here. Sized to match `DrainDownloadQueue`'s own cap: more threads
     * than Dart will ever fill is just idle threads.
     *
     * [imageStoreExecutor] stays serial for listing, deleting and preview
     * caching. Those have no reason to overlap, and their ordering is free
     * correctness that a pool would give away for nothing.
     */
    private val downloadExecutor: ExecutorService =
        Executors.newFixedThreadPool(MAX_CONCURRENT_DOWNLOADS)
    private var pendingOutsideGalleryGrant: PendingOutsideGalleryGrant? = null
    private var pendingGalleryDeletion: PendingGalleryDeletion? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WALLPAPER_CHANNEL,
        ).setMethodCallHandler(::handleWallpaperCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            IMAGE_STORE_CHANNEL,
        ).setMethodCallHandler(::handleImageStoreCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCREEN_CHANNEL,
        ).setMethodCallHandler(::handleScreenCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL,
        ).setMethodCallHandler(::handleShareCall)
    }

    /**
     * Turns FLAG_SECURE on and off for the private library.
     *
     * The flag belongs to the window, not to a route, so the screen that needs
     * it asks for it on the way in and gives it back on the way out. Left on, it
     * would block screenshots of the whole app; never set, an explicit wallpaper
     * would sit in the app-switcher thumbnail for anyone to see.
     */
    private fun handleScreenCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "setSecure") {
            result.notImplemented()
            return
        }
        if (call.argument<Boolean>("secure") == true) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        result.success(null)
    }

    override fun onDestroy() {
        wallpaperExecutor.shutdown()
        imageStoreExecutor.shutdown()
        downloadExecutor.shutdown()
        shareExecutor.shutdown()
        super.onDestroy()
    }

    /**
     * Shares a wallpaper out through Android's chooser.
     *
     * A link resolves on the UI thread — it launches an intent and nothing more.
     * An image must first be downloaded, so it runs on [shareExecutor] and hops
     * back to launch the chooser, which Android requires on the UI thread.
     */
    private fun handleShareCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shareLink" -> handleShareLink(call, result)
            "shareImage" -> handleShareImage(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleShareLink(call: MethodCall, result: MethodChannel.Result) {
        val page = call.argument<String>("page") ?: run {
            result.success(failure("noTarget"))
            return
        }
        result.success(WallpaperSharing(this).shareLink(page))
    }

    private fun handleShareImage(call: MethodCall, result: MethodChannel.Result) {
        val source = call.argument<String>("source")
        val fileName = call.argument<String>("fileName")
        if (source == null || fileName == null) {
            result.success(failure("downloadFailed"))
            return
        }
        shareExecutor.execute {
            val sharing = WallpaperSharing(this)
            val file = sharing.downloadToShareCache(source, fileName)
            runOnUiThread {
                val response = if (file == null) {
                    failure("downloadFailed")
                } else {
                    sharing.shareImageFile(file)
                }
                result.success(response)
            }
        }
    }

    private fun handleWallpaperCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "applyWallpaper" -> handleApplyWallpaper(call, result)
            "applyCroppedWallpaper" -> handleApplyCroppedWallpaper(call, result)
            "adjustWallpaper" -> handleAdjustWallpaper(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleApplyWallpaper(call: MethodCall, result: MethodChannel.Result) {
        val source = call.argument<String>("source")
        val target = call.argument<String>("target")
        if (source == null || target == null) {
            result.success(failure("unsupported"))
            return
        }
        wallpaperExecutor.execute {
            val response = applyWallpaper(Uri.parse(source), target)
            runOnUiThread { result.success(response) }
        }
    }

    /**
     * Applies a crop the user framed in tela's own editor.
     *
     * Same fetch-then-apply shape as [handleApplyWallpaper], off the UI thread;
     * only the apply differs — a region decode rather than a whole-image stream.
     */
    private fun handleApplyCroppedWallpaper(call: MethodCall, result: MethodChannel.Result) {
        val source = call.argument<String>("source")
        val target = call.argument<String>("target")
        val region = cropRectFrom(call)
        if (source == null || target == null || region == null) {
            result.success(failure("unsupported"))
            return
        }
        wallpaperExecutor.execute {
            val response = applyCroppedWallpaper(Uri.parse(source), target, region)
            runOnUiThread { result.success(response) }
        }
    }

    private fun cropRectFrom(call: MethodCall): Rect? {
        val left = call.argument<String>("left")?.toIntOrNull() ?: return null
        val top = call.argument<String>("top")?.toIntOrNull() ?: return null
        val width = call.argument<String>("width")?.toIntOrNull() ?: return null
        val height = call.argument<String>("height")?.toIntOrNull() ?: return null
        if (width <= 0 || height <= 0) return null
        return Rect(left, top, left + width, top + height)
    }

    private fun applyCroppedWallpaper(source: Uri, target: String, region: Rect): Map<String, Any> {
        val remote = source.scheme == "http" || source.scheme == "https"
        val cachedImage = try {
            if (remote) downloadToCache(source.toString()) else copyLocalToCache(source)
        } catch (_: Exception) {
            return failure(if (remote) "downloadFailed" else "sourceUnreadable")
        }
        return try {
            WallpaperCropApplying(this).apply(cachedImage, region, target)
            mapOf("success" to true)
        } catch (_: Exception) {
            failure("applyFailed")
        } finally {
            cachedImage.delete()
        }
    }

    /**
     * Hands the image to Android's own crop-and-set editor.
     *
     * Same shape as handleShareImage, and for the same reason: the download
     * must leave the UI thread and starting the activity must return to it.
     */
    private fun handleAdjustWallpaper(call: MethodCall, result: MethodChannel.Result) {
        val source = call.argument<String>("source")
        val fileName = call.argument<String>("fileName")
        if (source == null || fileName == null) {
            result.success(failure("downloadFailed"))
            return
        }
        wallpaperExecutor.execute {
            val editing = SystemWallpaperEditing(this)
            val file = editing.downloadToCache(source, fileName)
            runOnUiThread {
                val response = if (file == null) {
                    failure("downloadFailed")
                } else {
                    editing.openEditorOn(file)
                }
                result.success(response)
            }
        }
    }

    private fun handleImageStoreCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "storeImage" -> handleStoreImage(call, result)
            "copyStoredImage" -> handleCopyStoredImage(call, result)
            "listPrivateImages" -> onStorageThread(result) { ImageStorage(this).listPrivate() }
            "deleteDownload" -> handleDeleteDownload(call, result)
            "deleteDownloads" -> handleDeleteDownloads(call, result)
            "galleryDeleteConfirmedBySystem" ->
                result.success(mapOf("confirmed" to systemConfirmsGalleryDelete()))
            "canReadImage" -> handleCanReadImage(call, result)
            "materializeImage" -> handleMaterializeImage(call, result)
            "releasePreview" -> handleReleasePreview(call, result)
            "describeDownloadLocation" -> handleDescribeDownloadLocation(result)
            "chooseDownloadFolder" -> handleChooseDownloadFolder(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleMaterializeImage(call: MethodCall, result: MethodChannel.Result) {
        val location = call.argument<String>("location") ?: run {
            result.success(mapOf("success" to false))
            return
        }
        onStorageThread(result) { ImageStorage(this).materialise(Uri.parse(location)) }
    }

    private fun handleReleasePreview(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path") ?: run {
            result.success(mapOf("success" to true))
            return
        }
        onStorageThread(result) { ImageStorage(this).releasePreview(path) }
    }

    private fun handleCanReadImage(call: MethodCall, result: MethodChannel.Result) {
        val location = call.argument<String>("location") ?: run {
            result.success(mapOf("success" to true, "readable" to false))
            return
        }
        onStorageThread(result) { ImageStorage(this).canRead(Uri.parse(location)) }
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
     * Why the files-outside-gallery folder can't take a download, or null when
     * it can. `notConfigured` when nothing was ever chosen — Dart runs the
     * chooser and retries. `folderUnavailable` when a folder is set but its
     * volume is gone, an ejected card: nothing is rerouted, and the toast says
     * "reconnect it" rather than offering setup for a folder that already
     * exists.
     */
    private fun outsideGalleryProblem(): String? {
        val tree = outsideGalleryTree() ?: return "notConfigured"
        return if (DownloadFolderDescribing(this).isAvailable(tree)) null else "folderUnavailable"
    }

    /** Describes the location off the UI thread; it does filesystem stats. */
    private fun handleDescribeDownloadLocation(result: MethodChannel.Result) {
        onStorageThread(result) {
            DownloadFolderDescribing(this).describe(outsideGalleryTree())
        }
    }

    /**
     * Opens the folder picker pointed at the chosen volume, no download waiting.
     *
     * The `kind` ("device" or "sdCard") pre-aims the picker so the user confirms
     * one folder instead of hunting through a blank tree browser — the whole
     * point of the device/card choice. A card asked for while the slot is empty
     * has no volume to aim at, so it answers `notConfigured` rather than opening
     * a picker that could land anywhere.
     */
    private fun handleChooseDownloadFolder(call: MethodCall, result: MethodChannel.Result) {
        val kind = call.argument<String>("kind") ?: run {
            result.success(imageStoreFailure("unavailable"))
            return
        }
        val intent = DownloadVolumes(this).openTreeIntentFor(kind) ?: run {
            result.success(imageStoreFailure("notConfigured"))
            return
        }
        requestOutsideGalleryDirectory(result, intent)
    }

    /**
     * Hard-deletes a downloaded file, routing the gallery tier by API level.
     *
     * appPrivate and the SAF document delete synchronously off the UI thread.
     * The gallery tier on API 30+ cannot: `MediaStore.createDeleteRequest`
     * shows the OS's own confirmation and returns through onActivityResult, so
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
        onStorageThread(result) { ImageStorage(this).deleteDownload(tier, uri) }
    }

    /**
     * Asks the OS to delete one gallery image — unless its row is already gone.
     *
     * Off the UI thread for the MediaStore query, then back onto it because only
     * an Activity can launch the confirmation. Same stale-row rule as
     * [planDeletions], which is where it is explained.
     */
    private fun confirmGalleryDeletion(uri: Uri, result: MethodChannel.Result) {
        imageStoreExecutor.execute {
            val live = ImageStorage(this).galleryRowExists(uri)
            runOnUiThread {
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
        imageStoreExecutor.execute {
            val plan = planDeletions(ImageStorage(this), items)
            runOnUiThread {
                if (plan.confirm.isEmpty()) {
                    result.success(deletionOutcome(plan.deleted))
                } else {
                    requestGalleryDeletions(plan.confirm, plan.deleted, result)
                }
            }
        }
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
     * Launches one system confirmation for every gallery delete in the batch.
     *
     * One at a time, exactly like [requestOutsideGalleryDirectory]: a second
     * request while one is pending is refused rather than overwriting it. The
     * user accepts or declines the whole set at once; [alreadyDeleted] are the
     * non-gallery files already removed, kept in the answer either way.
     */
    @RequiresApi(Build.VERSION_CODES.R)
    private fun requestGalleryDeletions(
        galleryUris: List<Uri>,
        alreadyDeleted: List<String>,
        result: MethodChannel.Result,
    ) {
        if (pendingGalleryDeletion != null) {
            result.success(imageStoreFailure("unavailable"))
            return
        }
        // Both calls are inside the guard on purpose. `createDeleteRequest` is
        // the one that actually threw (a stale row, which [planDeletions] now
        // filters out); it ran outside the `try` while the `catch` guarded
        // `startIntentSenderForResult` against a different exception entirely,
        // and an uncaught throw here is on the main thread — it kills the app.
        try {
            val request = MediaStore.createDeleteRequest(contentResolver, galleryUris)
            pendingGalleryDeletion = PendingGalleryDeletion(
                result,
                galleryUris.map { it.toString() },
                alreadyDeleted,
            )
            startIntentSenderForResult(request.intentSender, GALLERY_DELETE_REQUEST, null, 0, 0, 0)
        } catch (_: Exception) {
            pendingGalleryDeletion = null
            result.success(deletionOutcome(alreadyDeleted))
        }
    }

    /**
     * A delete batch's answer: what went, whether or not everything did.
     *
     * Always a success, because "some of these were already gone" and "the user
     * declined the prompt" are outcomes, not failures — Dart forgets exactly the
     * rows named here and leaves the others alone.
     */
    private fun deletionOutcome(deleted: List<String>): Map<String, Any> =
        mapOf("success" to true, "deleted" to deleted)

    /** Runs filesystem work off the UI thread, answering on it. */
    private fun onStorageThread(
        result: MethodChannel.Result,
        work: () -> Map<String, Any>,
    ) {
        imageStoreExecutor.execute {
            val response = try {
                work()
            } catch (_: Exception) {
                imageStoreFailure("unavailable")
            }
            runOnUiThread { result.success(response) }
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
        // On [downloadExecutor] for the same reason a download is: this is bulk
        // file I/O, and a selection of thirty would otherwise queue behind the
        // serial storage thread that listing and deleting share.
        downloadExecutor.execute {
            val response = ImageStorage(this).copy(request, outsideGalleryTree())
            runOnUiThread { result.success(response) }
        }
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

    /**
     * Starts the folder picker for the Settings device/card chooser.
     *
     * [intent] is always pre-aimed at the chosen volume by [DownloadVolumes], so
     * the user confirms one folder instead of navigating a blank tree. Downloads
     * no longer open a picker here — an unconfigured one answers notConfigured
     * and the Flutter chooser takes over. The persistable-grant flags are added
     * here so no caller can forget them.
     */
    private fun requestOutsideGalleryDirectory(
        result: MethodChannel.Result,
        intent: Intent,
    ) {
        if (pendingOutsideGalleryGrant != null) {
            result.success(imageStoreFailure("notConfigured"))
            return
        }
        pendingOutsideGalleryGrant = PendingOutsideGalleryGrant(result)
        startActivityForResult(
            intent.addFlags(DIRECTORY_ACCESS_FLAGS),
            OUTSIDE_GALLERY_DIRECTORY_REQUEST,
        )
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            OUTSIDE_GALLERY_DIRECTORY_REQUEST -> onOutsideGalleryGrant(resultCode, data)
            GALLERY_DELETE_REQUEST -> onGalleryDeletion(resultCode)
        }
    }

    /**
     * Reads the system delete prompt's outcome and answers the whole batch.
     *
     * RESULT_OK means every gallery file in the prompt is gone; anything else
     * means the user dismissed it and none of that subset went — not a failure,
     * so the non-gallery files already deleted are still reported. The Dart use
     * case forgets exactly the rows whose locations come back here.
     */
    private fun onGalleryDeletion(resultCode: Int) {
        val pending = pendingGalleryDeletion ?: return
        pendingGalleryDeletion = null
        val deleted = pending.alreadyDeleted +
            if (resultCode == RESULT_OK) pending.galleryLocations else emptyList()
        pending.result.success(deletionOutcome(deleted))
    }

    private fun onOutsideGalleryGrant(resultCode: Int, data: Intent?) {
        val pending = pendingOutsideGalleryGrant ?: return
        pendingOutsideGalleryGrant = null
        val tree = data?.data
        if (resultCode != RESULT_OK || tree == null || !saveOutsideGalleryTree(tree, data.flags)) {
            pending.result.success(imageStoreFailure("notConfigured"))
            return
        }
        // The only caller is the device/card chooser, so answer with the
        // location the grant produced; the screen redraws without a second round
        // trip, and the Dart coordinator retries the download it stands in for.
        handleDescribeDownloadLocation(pending.result)
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
            contentResolver.takePersistableUriPermission(tree, grantedFlags)
            getSharedPreferences(PREFERENCES, MODE_PRIVATE)
                .edit()
                .putString(OUTSIDE_GALLERY_TREE, tree.toString())
                .apply()
            true
        } catch (_: SecurityException) {
            false
        }
    }

    private fun outsideGalleryTree(): String? {
        return getSharedPreferences(PREFERENCES, MODE_PRIVATE)
            .getString(OUTSIDE_GALLERY_TREE, null)
    }

    /**
     * Downloads on [downloadExecutor], never on [imageStoreExecutor].
     *
     * This one routing line is what makes a batch faster: the store streams the
     * image before it writes, so on the serial executor every download in a
     * queue waited for the one in front of it however many Dart ran at once.
     */
    private fun storeImage(request: ImageStoreRequest, result: MethodChannel.Result) {
        downloadExecutor.execute {
            val response = ImageStorage(this).store(request, outsideGalleryTree())
            runOnUiThread { result.success(response) }
        }
    }

    /**
     * Applies a wallpaper from Wallhaven, or from a file already on this device.
     *
     * A past download is set again from its own file: re-fetching several
     * megabytes tela already wrote is both slow and pointless, and it would make
     * "set again" need a network the user may not have. Which failure comes back
     * matters — an unreadable local file is how Dart learns the download was
     * deleted behind our back and that it should fall back to the source URL.
     */
    private fun applyWallpaper(source: Uri, target: String): Map<String, Any> {
        val remote = source.scheme == "http" || source.scheme == "https"
        val cachedImage = try {
            if (remote) downloadToCache(source.toString()) else copyLocalToCache(source)
        } catch (_: Exception) {
            return failure(if (remote) "downloadFailed" else "sourceUnreadable")
        }
        return try {
            applyCachedWallpaper(cachedImage, target)
            mapOf("success" to true)
        } catch (_: Exception) {
            failure("applyFailed")
        } finally {
            cachedImage.delete()
        }
    }

    private fun downloadToCache(imageUrl: String): File {
        val cachedImage = File.createTempFile("tela-wallpaper-", ".image", cacheDir)
        try {
            Downloads.fetch(imageUrl, cachedImage)
            return cachedImage
        } catch (error: Exception) {
            cachedImage.delete()
            throw error
        }
    }

    /**
     * Reads through the ContentResolver, which covers all three storage tiers:
     * a MediaStore image tela inserted, a document under the user's SAF tree, and
     * a plain file in app-private storage. Throws when the file is gone.
     */
    private fun copyLocalToCache(source: Uri): File {
        val stream = contentResolver.openInputStream(source)
            ?: throw IllegalStateException("no input stream for the stored image")
        return stream.use(::copyToCache)
    }

    private fun copyToCache(input: InputStream): File {
        val cachedImage = File.createTempFile("tela-wallpaper-", ".image", cacheDir)
        try {
            cachedImage.outputStream().use { output -> input.copyTo(output) }
            return cachedImage
        } catch (error: Exception) {
            cachedImage.delete()
            throw error
        }
    }

    private fun applyCachedWallpaper(cachedImage: File, target: String) {
        val wallpaper = WallpaperManager.getInstance(this)
        when (target) {
            "home" -> setWallpaper(wallpaper, cachedImage, WallpaperManager.FLAG_SYSTEM)
            "lock" -> setWallpaper(wallpaper, cachedImage, WallpaperManager.FLAG_LOCK)
            "both" -> setBothWallpapers(wallpaper, cachedImage)
            else -> throw IllegalArgumentException("target must be home|lock|both")
        }
    }

    private fun setBothWallpapers(wallpaper: WallpaperManager, cachedImage: File) {
        setWallpaper(wallpaper, cachedImage, WallpaperManager.FLAG_SYSTEM)
        // Restrictive OEMs need distinct writes; a combined flag often changes only home.
        Thread.sleep(BETWEEN_TARGETS_DELAY_MS)
        setWallpaper(wallpaper, cachedImage, WallpaperManager.FLAG_LOCK)
    }

    private fun setWallpaper(wallpaper: WallpaperManager, image: File, flag: Int) {
        image.inputStream().use { stream ->
            wallpaper.setStream(stream, null, true, flag)
        }
    }

    private fun failure(code: String): Map<String, Any> = mapOf(
        "success" to false,
        "errorCode" to code,
    )

    private fun imageStoreFailure(code: String): Map<String, Any> = mapOf(
        "success" to false,
        "errorCode" to code,
    )

    /** A device/card folder picker in flight, awaiting the user's grant. */
    private data class PendingOutsideGalleryGrant(
        val result: MethodChannel.Result,
    )

    /**
     * A system gallery-delete prompt in flight, awaiting the user's answer.
     *
     * [galleryLocations] go into the deleted set only if the user accepts;
     * [alreadyDeleted] — the non-gallery files removed before the prompt — are
     * kept either way.
     */
    private data class PendingGalleryDeletion(
        val result: MethodChannel.Result,
        val galleryLocations: List<String>,
        val alreadyDeleted: List<String>,
    )

    private companion object {
        const val WALLPAPER_CHANNEL = "cc.pym.tela/wallpaper"
        const val IMAGE_STORE_CHANNEL = "cc.pym.tela/images"
        const val SCREEN_CHANNEL = "cc.pym.tela/screen"
        const val SHARE_CHANNEL = "cc.pym.tela/share"
        const val OUTSIDE_GALLERY_DIRECTORY_REQUEST = 401
        const val GALLERY_DELETE_REQUEST = 402
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
        const val BETWEEN_TARGETS_DELAY_MS = 500L
    }
}
