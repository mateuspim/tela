import 'package:tela/data/db/tela_database.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/wallpaper.dart';
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
  Future<bool> isFavorite(String wallpaperId) => _db.hasFavorite(wallpaperId);

  @override
  Future<void> save(Wallpaper wallpaper) => _db.putFavorite(_toRow(wallpaper));

  @override
  Future<void> forget(String wallpaperId) => _db.deleteFavorite(wallpaperId);

  FavoriteWallpapersCompanion _toRow(Wallpaper wallpaper) {
    return FavoriteWallpapersCompanion.insert(
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
      colors: wallpaper.colors.join(','),
      savedAt: _now(),
    );
  }

  Wallpaper _toWallpaper(FavoriteRow row) {
    return Wallpaper(
      id: row.id,
      fullImageUrl: row.fullImageUrl,
      thumbSmallUrl: row.thumbSmallUrl,
      thumbLargeUrl: row.thumbLargeUrl,
      thumbOriginalUrl: row.thumbOriginalUrl,
      resolution: Resolution(row.width, row.height),
      fileSizeBytes: row.fileSizeBytes,
      purity: _purity(row.purity),
      category: _category(row.category),
      colors: _colors(row.colors),
    );
  }

  /// Reads a stored purity, treating an unrecognised one as [Purity.nsfw].
  ///
  /// Deliberately fails *closed*, unlike every other fallback in this codebase.
  /// Purity is what routes a download and what gates MediaStore indexing, so a
  /// corrupt row read as `sfw` is the one mistake that could index an explicit
  /// image. Read as `nsfw` it is merely over-protected, which is survivable.
  Purity _purity(String stored) {
    return Purity.values
            .where((Purity purity) => purity.name == stored)
            .firstOrNull ??
        Purity.nsfw;
  }

  Category _category(String stored) {
    return Category.values
            .where((Category category) => category.name == stored)
            .firstOrNull ??
        Category.general;
  }

  /// Splits the comma-joined colours, mapping an empty cell to no colours
  /// rather than to a list holding one empty string.
  List<String> _colors(String stored) {
    if (stored.isEmpty) return const <String>[];
    return stored.split(',');
  }
}
