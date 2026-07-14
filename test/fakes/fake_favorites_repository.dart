import 'package:tela/domain/models/wallpaper.dart';
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
  Future<bool> isFavorite(String wallpaperId) async =>
      _saved.any((Wallpaper w) => w.id == wallpaperId);

  @override
  Future<void> save(Wallpaper wallpaper) async {
    saveCount++;
    _saved
      ..removeWhere((Wallpaper w) => w.id == wallpaper.id)
      ..add(wallpaper);
  }

  @override
  Future<void> forget(String wallpaperId) async {
    _saved.removeWhere((Wallpaper w) => w.id == wallpaperId);
  }
}
