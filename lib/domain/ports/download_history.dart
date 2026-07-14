import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';

/// What this device has downloaded, so it can be set again without re-fetching.
///
/// A pure-domain port: Wallhaven has no idea these exist, and the fact that its
/// adapter speaks SQL is not something a use case may observe.
///
/// **Explicit wallpapers are never recorded here**, in any tier. They already
/// have a home — the private library, which lists the real files behind
/// `FLAG_SECURE` and the app-lock. A history row is the opposite of that: an
/// ungated, backed-up index of thumbnails and URLs, which is precisely what the
/// app-private tier exists to prevent. Implementations enforce this themselves;
/// callers must not have to remember it.
abstract interface class DownloadHistory {
  /// Every recorded download, most recent first. Never explicit ones.
  Future<List<DownloadRecord>> downloads();

  /// Records one completed download, replacing any earlier row for the same id.
  ///
  /// Silently keeps explicit wallpapers out rather than throwing: the file is
  /// already safely on disk by the time this runs, and a refused *history*
  /// write must not read to the user as a failed download.
  Future<void> record({
    required Wallpaper wallpaper,
    required StorageTier tier,
    required Uri location,
  });
}
