import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/favorites_repository.dart';

/// In-memory [FavoritesRepository], newest save first.
class FakeFavoritesRepository implements FavoritesRepository {
  /// Creates a fake holding [initial], oldest first.
  FakeFavoritesRepository({List<Wallpaper> initial = const <Wallpaper>[]})
    : _saved = List<Wallpaper>.of(initial);

  final List<Wallpaper> _saved;

  /// How many times [save] ran — pins that a toggle-off does not re-save.
  int saveCount = 0;

  @override
  Future<List<Wallpaper>> favorites() async => _saved.reversed.toList();

  @override
  Future<bool> isFavorite(WallpaperRef ref) async =>
      _saved.any((Wallpaper w) => w.ref == ref);

  @override
  Future<void> save(Wallpaper wallpaper) async {
    saveCount++;
    _saved
      ..removeWhere((Wallpaper w) => w.ref == wallpaper.ref)
      ..add(wallpaper);
  }

  @override
  Future<void> forget(WallpaperRef ref) async {
    _saved.removeWhere((Wallpaper w) => w.ref == ref);
  }
}
