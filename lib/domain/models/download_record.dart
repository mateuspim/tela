import 'package:meta/meta.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';

/// One wallpaper this device has already downloaded, and where it landed.
///
/// Carries the whole [Wallpaper] rather than an id: the history grid must
/// render with no network, and [wallpaper] is also the fallback source when the
/// file at [location] has since been deleted from the gallery.
///
/// ```dart
/// await applyDownload(download, WallpaperTarget.home); // no re-fetch
/// ```
@immutable
class DownloadRecord {
  /// Creates a record of one completed download.
  const DownloadRecord({
    required this.wallpaper,
    required this.tier,
    required this.location,
    required this.downloadedAt,
  });

  /// What was downloaded, whole — the grid renders from this offline.
  final Wallpaper wallpaper;

  /// The tier the download actually landed in, override included.
  final StorageTier tier;

  /// Where the file sits: a MediaStore or document URI, or a local file URI.
  final Uri location;

  /// When it was downloaded. Orders the history, newest first.
  final DateTime downloadedAt;

  @override
  bool operator ==(Object other) =>
      other is DownloadRecord && other.wallpaper.id == wallpaper.id;

  @override
  int get hashCode => wallpaper.id.hashCode;

  /// Names the download without naming where it lives, matching the rule that
  /// keeps stored paths out of logs.
  @override
  String toString() => 'DownloadRecord(${wallpaper.id}, ${tier.name})';
}
