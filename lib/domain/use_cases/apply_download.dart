import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/ports/wallpaper_applier.dart';

/// Sets an already-downloaded wallpaper again, from the copy on this device.
///
/// ```dart
/// await applyDownload(download, WallpaperTarget.both);
/// ```
class ApplyDownload {
  /// Creates the use case over the platform-independent [applier] port.
  const ApplyDownload({required WallpaperApplier applier}) : _applier = applier;

  final WallpaperApplier _applier;

  /// Applies [download] to [target], reading the file it already left behind.
  ///
  /// Falls back to Wallhaven when that file cannot be read — a gallery
  /// download can be deleted from Photos, and a document one from a file
  /// manager, neither of which tela hears about. The history row still knows
  /// the source URL, so a deleted file costs a re-fetch, not the feature.
  ///
  /// Only an unreadable source is retried: a wallpaper Android itself rejected
  /// would fail the same way the second time, at the price of a needless
  /// download.
  Future<void> call(DownloadRecord download, WallpaperTarget target) async {
    try {
      await _applier.apply(source: download.location, target: target);
    } on WallpaperApplyFailure catch (failure) {
      if (failure.problem != WallpaperApplyProblem.source) rethrow;
      await _applier.apply(
        source: Uri.parse(download.wallpaper.fullImageUrl),
        target: target,
      );
    }
  }
}
