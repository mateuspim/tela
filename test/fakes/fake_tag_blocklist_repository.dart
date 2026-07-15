import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/ports/tag_blocklist_repository.dart';

/// In-memory [TagBlocklistRepository], most recently blocked first.
class FakeTagBlocklistRepository implements TagBlocklistRepository {
  /// Creates a fake holding [initial], oldest first.
  FakeTagBlocklistRepository({
    List<WallpaperTag> initial = const <WallpaperTag>[],
  }) : _blocked = List<WallpaperTag>.of(initial);

  final List<WallpaperTag> _blocked;

  @override
  Future<List<WallpaperTag>> all() async => _blocked.reversed.toList();

  @override
  Future<Set<String>> blockedNames() async =>
      _blocked.map((WallpaperTag tag) => tag.name).toSet();

  /// Every currently blocked id — what tests assert on to prove a block
  /// (or unblock) actually reached the store.
  Set<int> blockedIds() => _blocked.map((WallpaperTag tag) => tag.id).toSet();

  @override
  Future<void> block(WallpaperTag tag) async {
    _blocked
      ..removeWhere((WallpaperTag t) => t.id == tag.id)
      ..add(tag);
  }

  @override
  Future<void> unblock(int tagId) async {
    _blocked.removeWhere((WallpaperTag t) => t.id == tagId);
  }
}
