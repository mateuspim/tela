import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/offload_run.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/storage_settings_controller.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/offload_group.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image_move.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/app_visibility.dart';

/// The offload in flight, or null when none is.
///
/// **At the composition root and never autoDispose**, which is the whole of
/// what "in the background" means here: the move outlives the screen that
/// started it, exactly as `downloadQueueControllerProvider` outlives the queue
/// tab. A controller owned by the settings screen would be torn down the moment
/// the user navigated away mid-copy.
final NotifierProvider<OffloadRunController, OffloadRun?> offloadRunProvider =
    NotifierProvider<OffloadRunController, OffloadRun?>(
      OffloadRunController.new,
    );

/// Runs one offload to completion, whatever the user does with the screen.
///
/// Holds no queue and nothing durable, unlike the download queue beside it, and
/// that difference is deliberate rather than an omission: a queued download can
/// be re-fetched from the network if the process dies, so a durable work list
/// costs nothing to replay. A half-finished move has already written bytes, and
/// replaying it blind would copy over files it had already moved. The recovery
/// story is instead that **every intermediate state is safe** — copies land,
/// originals stay, and a history row is re-pointed only for a file that really
/// completed the trip — so a killed process leaves duplicates the next offload
/// simply moves again, never a loss.
class OffloadRunController extends Notifier<OffloadRun?> {
  bool _stopRequested = false;
  bool _running = false;

  @override
  OffloadRun? build() => null;

  /// Starts moving [groups] onto the card. Returns at once.
  ///
  /// Refuses to start a second run while one is in flight: two moves over
  /// overlapping selections would each copy what the other is deleting.
  /// Answers whether this call started one.
  bool start(List<OffloadGroup> groups) {
    if (_running) return false;
    final List<StoredImageMove> moves = <StoredImageMove>[
      for (final OffloadGroup group in groups) ...group.moves,
    ];
    if (moves.isEmpty) return false;
    _running = true;
    _stopRequested = false;
    state = OffloadRun(
      phase: OffloadPhase.copying,
      total: moves.length,
      bytes: groups.fold(0, (int sum, OffloadGroup g) => sum + g.bytes),
      includesPrivateLibrary: groups.any(
        (OffloadGroup g) => g.kind == OffloadKind.privateLibrary,
      ),
    );
    unawaited(_run(moves));
    return true;
  }

  /// Stops copying. What is already copied still completes its move.
  ///
  /// Not a cancel, and the wording on the button says so. The alternative —
  /// undoing every copy made so far — would throw away the minutes of work the
  /// user is impatient about, which is the opposite of what pressing stop
  /// means.
  void stop() {
    if (!_running) return;
    _stopRequested = true;
    state = state?.at(state!.phase, stopping: true);
  }

  /// Clears a finished run, so the screen stops reporting it.
  void acknowledge() {
    if (_running) return;
    state = null;
  }

  Future<void> _run(List<StoredImageMove> moves) async {
    try {
      final Set<WallpaperRef> moved = await ref.read(moveStoredImagesProvider)(
        moves,
        onCopied: _onCopied,
        stopped: () => _stopRequested,
        beforeDelete: _awaitScreen,
      );
      if (moved.isNotEmpty) await _reroute();
      _finish(moved.length);
    } on ImageStoreFailure {
      _finish(0, failed: true);
    } finally {
      _running = false;
    }
  }

  void _onCopied(int copied, int total) {
    state = state?.at(OffloadPhase.copying, copied: copied);
  }

  /// Holds the delete until there is a screen to raise the OS prompt on.
  ///
  /// See [AppVisibility]: with no Activity attached a gallery delete cannot
  /// happen, and a move reads that as declined and undoes every copy behind it.
  /// The phase is published so the screen — and anyone reading the shade — can
  /// say *why* a finished-looking copy has not finished.
  Future<void> _awaitScreen() async {
    final AppVisibility visibility = ref.read(appVisibilityProvider);
    if (visibility.isForeground) {
      state = state?.at(OffloadPhase.removing);
      return;
    }
    state = state?.at(OffloadPhase.waitingForScreen);
    await visibility.whenForeground();
    state = state?.at(OffloadPhase.removing);
  }

  void _finish(int moved, {bool failed = false}) {
    refreshDownloadsFrom(ref);
    state = state?.at(OffloadPhase.done, moved: moved, failed: failed);
  }

  /// Sends future downloads to the card as well — the half of the promise the
  /// move itself cannot keep.
  ///
  /// Safe content always. **Explicit content only when the private library was
  /// part of the move**: leaving it on the app-private tier would start
  /// refilling the storage just cleared, while re-routing it for someone who
  /// never ticked that group would put explicit downloads on a removable card
  /// they did not ask to put them on.
  Future<void> _reroute() async {
    // Awaited before either write: the controller ignores a route asked of it
    // while its own load is still in flight, and a background run can easily be
    // the first thing in the process to touch it.
    await ref.read(storageSettingsProvider.future);
    final StorageSettingsController settings = ref.read(
      storageSettingsProvider.notifier,
    );
    await settings.route(Purity.sfw, StorageTier.filesOutsideGallery);
    if (state?.includesPrivateLibrary != true) return;
    await settings.route(Purity.nsfw, StorageTier.filesOutsideGallery);
    // Batch choices are stored as explicit destinations. Without migrating
    // them, an older private batch can refill the internal directory after the
    // library has moved even though newly queued work follows this setting.
    await ref
        .read(downloadQueueProvider)
        .reroute(
          StorageTier.appPrivate,
          StorageTier.filesOutsideGallery,
        );
  }
}
