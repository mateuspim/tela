import 'package:drift/drift.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/ports/tag_blocklist_repository.dart';

/// Stores the tag blocklist as rows in tela's SQLite database.
///
/// ```dart
/// final TagBlocklistRepository blocklist = DriftTagBlocklistRepository(db);
/// await blocklist.block(tag);
/// ```
class DriftTagBlocklistRepository implements TagBlocklistRepository {
  /// Creates the adapter over an open [TelaDatabase].
  ///
  /// [now] is injected so a test can pin block order without sleeping between
  /// writes; the app passes `DateTime.now`.
  const DriftTagBlocklistRepository(
    this._db, {
    DateTime Function() now = _wallClock,
  }) : _now = now;

  static DateTime _wallClock() => DateTime.now();

  final TelaDatabase _db;
  final DateTime Function() _now;

  @override
  Future<List<WallpaperTag>> all() async {
    final List<BlockedTagRow> rows = await _db.blockedTagRows();
    return rows.map(_toTag).toList();
  }

  @override
  Future<Set<String>> blockedNames() async {
    final List<BlockedTagRow> rows = await _db.blockedTagRows();
    return rows.map((BlockedTagRow row) => row.name).toSet();
  }

  @override
  Future<void> block(WallpaperTag tag) {
    return _db.putBlockedTag(
      BlockedTagsCompanion.insert(
        id: Value(tag.id),
        name: tag.name,
        blockedAt: _now(),
      ),
    );
  }

  @override
  Future<void> unblock(int tagId) => _db.deleteBlockedTag(tagId);

  WallpaperTag _toTag(BlockedTagRow row) =>
      WallpaperTag(id: row.id, name: row.name);
}
