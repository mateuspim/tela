import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/download_location.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/ports/image_store.dart';
import 'package:tela/domain/use_cases/download_wallpaper.dart';

/// How a download that may need first-time folder setup turned out.
enum DownloadOutcome {
  /// The file was written.
  saved,

  /// The user dismissed the folder chooser. Nothing was written, and this is
  /// deliberately not a failure to report — they chose to stop.
  cancelled,

  /// The chosen folder is set but its volume is gone — an ejected card. Nothing
  /// was written and nothing was rerouted; the message says to reconnect it,
  /// not to set one up, so it is distinct from [failed] and [cancelled].
  folderUnavailable,

  /// The download itself failed.
  failed,
}

/// Runs the device/card chooser, resolving to the picked volume or null.
///
/// [offerSdCard] hides the card row when no card is on offer, the same rule the
/// Settings chooser uses.
typedef ChooseDownloadVolume =
    Future<StorageVolumeKind?> Function({required bool offerSdCard});

/// A download that sets up the files-outside-gallery folder on first use.
///
/// That tier grants its folder through a system picker, and until slice 2 the
/// picker was a blank tree browser Android opened mid-download — no "device or
/// SD card" choice, no pre-aiming. This wraps a download so the *first* one to
/// that tier runs the same device/card chooser Settings does, grants a pre-aimed
/// folder, then retries — instead of the blank browser.
///
/// It stays UI-free on purpose: the chooser is injected as
/// [ChooseDownloadVolume] so the retry logic is plain-Dart testable, and the
/// widget layer supplies the bottom sheet.
///
/// ```dart
/// final DownloadOutcome outcome = await configuredDownload(
///   wallpaper,
///   chooseVolume: ({required bool offerSdCard}) =>
///       chooseDownloadVolume(context, offerSdCard: offerSdCard),
/// );
/// ```
class ConfiguredDownload {
  /// Creates the coordinator over the download and the folder-granting store.
  const ConfiguredDownload({
    required PerformDownload perform,
    required ImageStore imageStore,
  }) : _perform = perform,
       _imageStore = imageStore;

  final PerformDownload _perform;
  final ImageStore _imageStore;

  /// Downloads [wallpaper], setting up a folder first when the tier needs one.
  ///
  /// [tier] is the per-download override, forwarded untouched. [chooseVolume]
  /// shows the device/card sheet; a dismissed sheet yields
  /// [DownloadOutcome.cancelled] with nothing written.
  Future<DownloadOutcome> call(
    Wallpaper wallpaper, {
    required ChooseDownloadVolume chooseVolume,
    StorageTier? tier,
  }) async {
    try {
      await _perform(wallpaper, tier: tier);
      return DownloadOutcome.saved;
    } on ImageStoreFailure catch (failure) {
      return switch (failure.problem) {
        // A configured folder is present but unwritable — never offer setup or
        // reroute; surface it so the user reconnects the storage.
        ImageStoreProblem.folderUnavailable =>
          DownloadOutcome.folderUnavailable,
        // Never configured: run the chooser, grant a folder, and retry once.
        ImageStoreProblem.notConfigured => await _setUpAndRetry(
          wallpaper,
          tier,
          chooseVolume,
        ),
        _ => DownloadOutcome.failed,
      };
    }
  }

  /// Grants the files-outside-gallery folder **before** any download runs,
  /// unless one is already granted.
  ///
  /// The batch path's entry point, and the reason it is public. A queued batch
  /// drains with no screen mounted, so it cannot answer a chooser the way
  /// [call] does — it has to settle first-time setup while there is still a
  /// screen, or every entry fails on the same unanswered question. True when a
  /// folder is granted (already, or just now); false when the user backed out.
  ///
  /// ```dart
  /// if (!await configuredDownload.ensureFolder(chooseVolume)) return;
  /// ```
  Future<bool> ensureFolder(ChooseDownloadVolume chooseVolume) async {
    final DownloadLocation location = await _imageStore.downloadLocation();
    if (location.folder != null) return true;
    return _grantFrom(location, chooseVolume);
  }

  /// Grants a folder through the chooser, then retries the download once.
  Future<DownloadOutcome> _setUpAndRetry(
    Wallpaper wallpaper,
    StorageTier? tier,
    ChooseDownloadVolume chooseVolume,
  ) async {
    if (!await _grantFolder(chooseVolume)) return DownloadOutcome.cancelled;
    return _retry(wallpaper, tier);
  }

  /// Opens the chooser — aimed by whether a card is on offer — and grants the
  /// pick. False when the user dismissed the sheet or the system picker.
  Future<bool> _grantFolder(ChooseDownloadVolume chooseVolume) async {
    final DownloadLocation location = await _imageStore.downloadLocation();
    return _grantFrom(location, chooseVolume);
  }

  /// The chooser half, over a [location] already read — so [ensureFolder] does
  /// not ask the store the same question twice.
  Future<bool> _grantFrom(
    DownloadLocation location,
    ChooseDownloadVolume chooseVolume,
  ) async {
    final StorageVolumeKind? kind = await chooseVolume(
      offerSdCard: location.offersSdCard,
    );
    if (kind == null) return false;
    final DownloadFolder? folder = await _imageStore.chooseDownloadFolder(kind);
    return folder != null;
  }

  /// One retry only: a second `notConfigured` means the grant did not take, and
  /// looping would reopen the picker forever.
  Future<DownloadOutcome> _retry(Wallpaper wallpaper, StorageTier? tier) async {
    try {
      await _perform(wallpaper, tier: tier);
      return DownloadOutcome.saved;
    } on ImageStoreFailure {
      return DownloadOutcome.failed;
    }
  }
}
