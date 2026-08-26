import 'package:drift/drift.dart';
import 'package:tela/data/db/stored_wallpaper_fields.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
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

  /// Reads the history back, dropping any row that is explicit or app-private.
  ///
  /// [record] is what keeps those rows out in the first place; this is the door
  /// behind it. A row whose purity is corrupt reads as `nsfw` by design, and
  /// the one thing that must not happen is an explicit thumbnail appearing on
  /// a screen with no `FLAG_SECURE` and no lock — so it is dropped, not shown.
  /// The tier check is the same argument for the same reason: a private
  /// download's index is the private library, never this list.
  ///
  /// The v5 migration purged the app-private rows written before that rule
  /// existed, so this filter is the door and not the cleanup — a row reaching
  /// it now would mean [record] let one through.
  @override
  Future<List<DownloadRecord>> downloads() async {
    final List<DownloadRow> rows = await _db.downloadRows();
    return rows.where(_isListable).map(_toRecord).toList();
  }

  bool _isListable(DownloadRow row) {
    if (storedPurity(row.purity) == Purity.nsfw) return false;
    return storedTier(row.tier) != StorageTier.appPrivate;
  }

  @override
  Future<void> record({
    required Wallpaper wallpaper,
    required StorageTier tier,
    required Uri location,
    TagFolder? tag,
  }) async {
    if (wallpaper.isNsfw) return;
    if (tier == StorageTier.appPrivate) return;
    await _db.putDownload(_toRow(wallpaper, tier, location, tag));
  }

  /// Re-points the row at a file that has moved tag. See
  /// [DownloadHistory.retag].
  @override
  Future<void> retag({
    required WallpaperRef ref,
    required Uri location,
    required TagFolder? tag,
  }) => _db.retagDownload(ref, location.toString(), tag?.name);

  /// Re-points the row at a file that has moved tier, or drops it when the new
  /// tier is one this list may not hold. See [DownloadHistory.relocate].
  ///
  /// The `appPrivate` branch is the same refusal [record] makes, arriving by
  /// the other door: a wallpaper moved into the private library must leave no
  /// row behind, and putting that rule here rather than in the use case is what
  /// keeps it true for every caller.
  @override
  Future<void> relocate({
    required WallpaperRef ref,
    required StorageTier tier,
    required Uri location,
    TagFolder? tag,
  }) {
    if (tier == StorageTier.appPrivate) return _db.deleteDownload(ref);
    return _db.relocateDownload(ref, tier.name, location.toString(), tag?.name);
  }

  /// Drops the row and nothing else — the downloaded file is not tela's to
  /// delete from here. See [DownloadHistory.forget].
  @override
  Future<void> forget(WallpaperRef ref) => _db.deleteDownload(ref);

  /// The bulk sibling of [forget]. See [DownloadHistory.forgetAll].
  @override
  Future<void> forgetAll(Iterable<WallpaperRef> refs) =>
      _db.deleteDownloads(refs);

  DownloadedWallpapersCompanion _toRow(
    Wallpaper wallpaper,
    StorageTier tier,
    Uri location,
    TagFolder? tag,
  ) {
    return DownloadedWallpapersCompanion.insert(
      source: wallpaper.source.value,
      pageUrl: wallpaper.pageUrl.toString(),
      id: wallpaper.id,
      fullImageUrl: wallpaper.fullImageUrl,
      thumbSmallUrl: wallpaper.thumbSmallUrl,
      thumbLargeUrl: wallpaper.thumbLargeUrl,
      thumbOriginalUrl: wallpaper.thumbOriginalUrl,
      width: wallpaper.resolution.width,
      height: wallpaper.resolution.height,
      fileSizeBytes: wallpaper.fileSizeBytes,
      purity: wallpaper.purity.name,
      category: storableCategory(wallpaper.category),
      colors: joinedColors(wallpaper.colors),
      tier: tier.name,
      location: location.toString(),
      downloadedAt: _now(),
      tag: Value<String?>(tag?.name),
    );
  }

  DownloadRecord _toRecord(DownloadRow row) {
    return DownloadRecord(
      wallpaper: _toWallpaper(row),
      tier: storedTier(row.tier),
      location: Uri.parse(row.location),
      downloadedAt: row.downloadedAt,
      // Unreadable rather than trusted: the column holds whatever was written,
      // and a name that is no longer a legal folder must not become one again
      // on the way out. `tryParse`'s null is the same "untagged" every
      // pre-v8 row reads back as.
      tag: storedTag(row.tag),
    );
  }

  Wallpaper _toWallpaper(DownloadRow row) {
    return Wallpaper(
      id: row.id,
      source: storedSource(row.source),
      pageUrl: Uri.parse(row.pageUrl),
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
