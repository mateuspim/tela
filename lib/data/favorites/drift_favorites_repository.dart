import 'package:tela/data/db/stored_wallpaper_fields.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/favorites_repository.dart';

/// Stores favorites as whole wallpaper rows in tela's SQLite database.
///
/// ```dart
/// final FavoritesRepository favorites = DriftFavoritesRepository(db, clock);
/// await favorites.save(wallpaper);
/// ```
class DriftFavoritesRepository implements FavoritesRepository {
  /// Creates the adapter over an open [TelaDatabase].
  ///
  /// [now] is injected so a test can pin save order without sleeping; the app
  /// passes `DateTime.now`.
  const DriftFavoritesRepository(
    this._db, {
    DateTime Function() now = _wallClock,
  }) : _now = now;

  static DateTime _wallClock() => DateTime.now();

  final TelaDatabase _db;
  final DateTime Function() _now;

  @override
  Future<List<Wallpaper>> favorites() async {
    final List<FavoriteRow> rows = await _db.favoriteRows();
    return rows.map(_toWallpaper).toList();
  }

  @override
  Future<bool> isFavorite(WallpaperRef ref) => _db.hasFavorite(ref);

  @override
  Future<void> save(Wallpaper wallpaper) => _db.putFavorite(_toRow(wallpaper));

  @override
  Future<void> forget(WallpaperRef ref) => _db.deleteFavorite(ref);

  FavoriteWallpapersCompanion _toRow(Wallpaper wallpaper) {
    return FavoriteWallpapersCompanion.insert(
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
      savedAt: _now(),
    );
  }

  Wallpaper _toWallpaper(FavoriteRow row) {
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
