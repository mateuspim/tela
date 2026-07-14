import 'package:tela/data/db/stored_wallpaper_fields.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/ports/download_history.dart';

/// Stores the download history as whole wallpaper rows in tela's database.
///
/// ```dart
/// final DownloadHistory history = DriftDownloadHistory(db);
/// await history.record(wallpaper: wallpaper, tier: tier, location: uri);
/// ```
class DriftDownloadHistory implements DownloadHistory {
  /// Creates the adapter over an open [TelaDatabase].
  ///
  /// [now] is injected so a test can pin download order without sleeping; the
  /// app passes `DateTime.now`.
  const DriftDownloadHistory(
    this._db, {
    DateTime Function() now = _wallClock,
  }) : _now = now;

  static DateTime _wallClock() => DateTime.now();

  final TelaDatabase _db;
  final DateTime Function() _now;

  /// Reads the history back, dropping any row that reads as explicit.
  ///
  /// [record] is what keeps those rows out in the first place; this is the door
  /// behind it. A row whose purity is corrupt reads as `nsfw` by design, and
  /// the one thing that must not happen is an explicit thumbnail appearing on
  /// a screen with no `FLAG_SECURE` and no lock — so it is dropped, not shown.
  @override
  Future<List<DownloadRecord>> downloads() async {
    final List<DownloadRow> rows = await _db.downloadRows();
    return rows
        .where((DownloadRow row) => storedPurity(row.purity) != Purity.nsfw)
        .map(_toRecord)
        .toList();
  }

  @override
  Future<void> record({
    required Wallpaper wallpaper,
    required StorageTier tier,
    required Uri location,
  }) async {
    if (wallpaper.isNsfw) return;
    await _db.putDownload(_toRow(wallpaper, tier, location));
  }

  /// Drops the row and nothing else — the downloaded file is not tela's to
  /// delete from here. See [DownloadHistory.forget].
  @override
  Future<void> forget(String id) => _db.deleteDownload(id);

  DownloadedWallpapersCompanion _toRow(
    Wallpaper wallpaper,
    StorageTier tier,
    Uri location,
  ) {
    return DownloadedWallpapersCompanion.insert(
      id: wallpaper.id,
      fullImageUrl: wallpaper.fullImageUrl,
      thumbSmallUrl: wallpaper.thumbSmallUrl,
      thumbLargeUrl: wallpaper.thumbLargeUrl,
      thumbOriginalUrl: wallpaper.thumbOriginalUrl,
      width: wallpaper.resolution.width,
      height: wallpaper.resolution.height,
      fileSizeBytes: wallpaper.fileSizeBytes,
      purity: wallpaper.purity.name,
      category: wallpaper.category.name,
      colors: joinedColors(wallpaper.colors),
      tier: tier.name,
      location: location.toString(),
      downloadedAt: _now(),
    );
  }

  DownloadRecord _toRecord(DownloadRow row) {
    return DownloadRecord(
      wallpaper: _toWallpaper(row),
      tier: storedTier(row.tier),
      location: Uri.parse(row.location),
      downloadedAt: row.downloadedAt,
    );
  }

  Wallpaper _toWallpaper(DownloadRow row) {
    return Wallpaper(
      id: row.id,
      fullImageUrl: row.fullImageUrl,
      thumbSmallUrl: row.thumbSmallUrl,
      thumbLargeUrl: row.thumbLargeUrl,
      thumbOriginalUrl: row.thumbOriginalUrl,
      resolution: Resolution(row.width, row.height),
      fileSizeBytes: row.fileSizeBytes,
      purity: storedPurity(row.purity),
      category: storedCategory(row.category),
      colors: storedColors(row.colors),
    );
  }
}
