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

/// The columns that spell out one whole wallpaper, shared by the tables that
/// keep one.
///
/// Both favorites and downloads store the wallpaper *whole* rather than as a
/// bare id, for the same reason: their grids must render with no network at
/// all, and an applied or re-applied wallpaper needs every field an id alone
/// would have to re-fetch. Sharing the columns keeps the two tables from
/// drifting apart field by field.
mixin WallpaperColumns on Table {
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

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// One favorited wallpaper, stored whole rather than as a bare id.
///
/// Every field the grid and the apply action need lives here, so the favorites
/// screen renders — and a saved wallpaper can still be applied — with no
/// network at all. An id-only table would make favorites unreadable offline,
/// which is the one thing they exist to survive.
@DataClassName('FavoriteRow')
class FavoriteWallpapers extends Table with WallpaperColumns {
  /// When it was favorited. Orders the grid, newest first.
  DateTimeColumn get savedAt => dateTime()();
}

/// One wallpaper this device downloaded, and where the file landed.
///
/// Keyed by wallpaper id, so downloading the same wallpaper twice updates one
/// row rather than stacking duplicates in the history.
///
/// **Never holds an explicit wallpaper.** Those live in the private library,
/// behind `FLAG_SECURE` and the app-lock; a row here would be an ungated index
/// of them, in a database Android's Auto Backup carries off the device.
@DataClassName('DownloadRow')
class DownloadedWallpapers extends Table with WallpaperColumns {
  /// `StorageTier` name of the destination it actually landed in.
  TextColumn get tier => text()();

  /// The file's URI: MediaStore content, a SAF document, or a local file.
  TextColumn get location => text()();

  /// When it was downloaded. Orders the history, newest first.
  DateTimeColumn get downloadedAt => dateTime()();
}

/// tela's local database: the one SQLite connection the app opens.
///
/// Adapters in `data/` own the meaning of what they store; features never see
/// this class, only the domain ports its adapters implement.
///
/// ```dart
/// final TelaDatabase db = TelaDatabase.open();
/// ```
@DriftDatabase(
  tables: <Type>[SettingEntries, FavoriteWallpapers, DownloadedWallpapers],
)
class TelaDatabase extends _$TelaDatabase {
  /// Wraps an existing connection — the seam tests use for an in-memory one.
  TelaDatabase(super.e);

  /// Opens the on-device database file.
  factory TelaDatabase.open() {
    return TelaDatabase(driftDatabase(name: 'tela'));
  }

  @override
  int get schemaVersion => 3;

  /// Adds tables to an existing database instead of recreating it.
  ///
  /// The settings table shipped at v1 with real user choices in it, and
  /// favorites at v2. A downloads table arriving at v3 must not cost anyone
  /// either — each version only ever adds what the one before it lacked.
  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) => m.createAll(),
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) await m.createTable(favoriteWallpapers);
        if (from < 3) await m.createTable(downloadedWallpapers);
      },
    );
  }

  /// Every download, most recent first.
  Future<List<DownloadRow>> downloadRows() {
    final SimpleSelectStatement<$DownloadedWallpapersTable, DownloadRow> query =
        select(downloadedWallpapers)
          ..orderBy(<OrderClauseGenerator<$DownloadedWallpapersTable>>[
            ($DownloadedWallpapersTable row) =>
                OrderingTerm.desc(row.downloadedAt),
          ]);
    return query.get();
  }

  /// Writes one download, replacing any earlier row for the same wallpaper.
  Future<void> putDownload(DownloadedWallpapersCompanion row) {
    return into(downloadedWallpapers).insertOnConflictUpdate(row);
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

  /// Removes settings. A key that was never written is not an error.
  ///
  /// Takes several keys because the callers delete a *setting*, and one setting
  /// can be more than one row — the account defaults are three.
  Future<void> deleteSettings(Iterable<String> keys) {
    final DeleteStatement<$SettingEntriesTable, SettingEntry> statement =
        delete(settingEntries)
          ..where(($SettingEntriesTable row) => row.key.isIn(keys));
    return statement.go();
  }
}
