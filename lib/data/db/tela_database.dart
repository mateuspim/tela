import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'tela_database.g.dart';

/// One persisted preference, addressed by a stable string key.
///
/// A key/value shape rather than a column per setting: settings arrive one
/// slice at a time, and a new one should be a new row, not a migration.
@DataClassName('SettingEntry')
class SettingEntries extends Table {
  /// The setting's stable identifier, e.g. `storage.tier.nsfw`.
  TextColumn get key => text()();

  /// The stored value, serialised by the adapter that owns the key.
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

/// One favorited wallpaper, stored whole rather than as a bare id.
///
/// Every field the grid and the apply action need lives here, so the favorites
/// screen renders — and a saved wallpaper can still be applied — with no
/// network at all. An id-only table would make favorites unreadable offline,
/// which is the one thing they exist to survive.
@DataClassName('FavoriteRow')
class FavoriteWallpapers extends Table {
  /// Wallhaven's id, e.g. `"e7jvjd"`.
  TextColumn get id => text()();

  /// Full-resolution source — what apply and download stream from.
  TextColumn get fullImageUrl => text()();

  /// The three Wallhaven thumbnail sizes, kept as-is.
  TextColumn get thumbSmallUrl => text()();

  /// Preview-sized thumbnail.
  TextColumn get thumbLargeUrl => text()();

  /// Ratio-preserving thumbnail — the one the masonry grid draws.
  TextColumn get thumbOriginalUrl => text()();

  /// Pixel width of [fullImageUrl].
  IntColumn get width => integer()();

  /// Pixel height of [fullImageUrl].
  IntColumn get height => integer()();

  /// Size of [fullImageUrl] in bytes.
  IntColumn get fileSizeBytes => integer()();

  /// Purity enum name. Routes storage, so its read has a fail-safe parse.
  TextColumn get purity => text()();

  /// Category enum name.
  TextColumn get category => text()();

  /// Dominant colours, comma-joined in Wallhaven's order.
  TextColumn get colors => text()();

  /// When it was favorited. Orders the grid, newest first.
  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// tela's local database: the one SQLite connection the app opens.
///
/// Adapters in `data/` own the meaning of what they store; features never see
/// this class, only the domain ports its adapters implement.
///
/// ```dart
/// final TelaDatabase db = TelaDatabase.open();
/// ```
@DriftDatabase(tables: <Type>[SettingEntries, FavoriteWallpapers])
class TelaDatabase extends _$TelaDatabase {
  /// Wraps an existing connection — the seam tests use for an in-memory one.
  TelaDatabase(super.e);

  /// Opens the on-device database file.
  factory TelaDatabase.open() {
    return TelaDatabase(driftDatabase(name: 'tela'));
  }

  @override
  int get schemaVersion => 2;

  /// Adds tables to an existing database instead of recreating it.
  ///
  /// The settings table shipped at v1 with real user choices in it. A favorites
  /// table arriving at v2 must not cost anyone their download destinations —
  /// or, once favorites ship, their favorites.
  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) => m.createAll(),
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) await m.createTable(favoriteWallpapers);
      },
    );
  }

  /// Every favorite, most recently saved first.
  Future<List<FavoriteRow>> favoriteRows() {
    final SimpleSelectStatement<$FavoriteWallpapersTable, FavoriteRow> query =
        select(favoriteWallpapers)
          ..orderBy(<OrderClauseGenerator<$FavoriteWallpapersTable>>[
            ($FavoriteWallpapersTable row) => OrderingTerm.desc(row.savedAt),
          ]);
    return query.get();
  }

  /// True when [id] is currently favorited.
  Future<bool> hasFavorite(String id) async {
    final SimpleSelectStatement<$FavoriteWallpapersTable, FavoriteRow> query =
        select(favoriteWallpapers)
          ..where(($FavoriteWallpapersTable row) => row.id.equals(id));
    return await query.getSingleOrNull() != null;
  }

  /// Writes one favorite, replacing any earlier row with the same id.
  Future<void> putFavorite(FavoriteWallpapersCompanion row) {
    return into(favoriteWallpapers).insertOnConflictUpdate(row);
  }

  /// Removes one favorite. A no-op when [id] was never saved.
  Future<void> deleteFavorite(String id) {
    final DeleteStatement<$FavoriteWallpapersTable, FavoriteRow> statement =
        delete(favoriteWallpapers)
          ..where(($FavoriteWallpapersTable row) => row.id.equals(id));
    return statement.go();
  }

  /// Reads one setting, or null when it was never written.
  Future<String?> settingValue(String key) {
    final SimpleSelectStatement<$SettingEntriesTable, SettingEntry> query =
        select(settingEntries)
          ..where(($SettingEntriesTable row) => row.key.equals(key));
    return query.map((SettingEntry row) => row.value).getSingleOrNull();
  }

  /// Writes one setting, replacing any previous value for [key].
  Future<void> putSetting(String key, String value) {
    return into(settingEntries).insertOnConflictUpdate(
      SettingEntriesCompanion.insert(key: key, value: value),
    );
  }
}
