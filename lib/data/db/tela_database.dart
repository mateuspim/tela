import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

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
  /// `SourceId` value of the site it came from, e.g. `"wallhaven"`.
  ///
  /// Half the primary key, and the reason there is one: an id is unique to its
  /// source, so two sources can issue the same one — Konachan #12345 and
  /// yande.re #12345 are two wallpapers, and a table keyed on the number alone
  /// would let the second silently overwrite the first.
  TextColumn get source => text()();

  /// The id that source issued, e.g. `"e7jvjd"`.
  TextColumn get id => text()();

  /// The wallpaper's public page on its own site.
  ///
  /// Stored rather than composed on read for the same reason the model stopped
  /// composing it: only the source's adapter knows its URL shape, and a stored
  /// row must render offline without one.
  TextColumn get pageUrl => text()();

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

  /// Category enum name, or empty for a source that has no such axis.
  TextColumn get category => text()();

  /// Dominant colours, comma-joined in Wallhaven's order.
  TextColumn get colors => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{source, id};
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
/// Keyed by source and id, so downloading the same wallpaper twice updates one
/// row rather than stacking duplicates in the history.
///
/// **Never holds an explicit wallpaper, and never an app-private one.** Both
/// live in the private library, behind `FLAG_SECURE` and the app-lock; a row
/// here would be an ungated index of them, in a database Android's Auto Backup
/// carries off the device. The tier rule is the one that is easy to miss: a
/// perfectly safe wallpaper sent to the `appPrivate` tier was sent there to be
/// private, and purity has nothing to say about that.
@DataClassName('DownloadRow')
class DownloadedWallpapers extends Table with WallpaperColumns {
  /// `StorageTier` name of the destination it actually landed in.
  TextColumn get tier => text()();

  /// The file's URI: MediaStore content, a SAF document, or a local file.
  TextColumn get location => text()();

  /// When it was downloaded. Orders the history, newest first.
  DateTimeColumn get downloadedAt => dateTime()();
}

/// One tag the user never wants to see again, kept by id so a rename upstream
/// cannot slip a blocked tag back into a listing.
@DataClassName('BlockedTagRow')
class BlockedTags extends Table {
  /// Wallhaven's numeric tag id — what the `-id:{n}` operator actually
  /// excludes.
  IntColumn get id => integer()();

  /// Display name, kept only so the management screen can show what was
  /// blocked without a network call.
  TextColumn get name => text()();

  /// When it was blocked. Orders the management screen, newest first.
  DateTimeColumn get blockedAt => dateTime()();

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
@DriftDatabase(
  tables: <Type>[
    SettingEntries,
    FavoriteWallpapers,
    DownloadedWallpapers,
    BlockedTags,
  ],
)
class TelaDatabase extends _$TelaDatabase {
  /// Wraps an existing connection — the seam tests use for an in-memory one.
  TelaDatabase(super.e);

  /// Opens the on-device database file.
  factory TelaDatabase.open() {
    return TelaDatabase(driftDatabase(name: 'tela'));
  }

  @override
  int get schemaVersion => 6;

  /// Adds tables to an existing database instead of recreating it.
  ///
  /// The settings table shipped at v1 with real user choices in it, favorites
  /// at v2, and downloads at v3. A blocked-tags table arriving at v4 must not
  /// cost anyone either — each version only ever adds what the one before it
  /// lacked. v5 is the exception that proves the shape: it adds nothing and
  /// *removes* rows, because those rows should never have been written. v6 is
  /// the other exception: it rewrites two tables, and every row they hold is
  /// kept.
  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) => m.createAll(),
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) await m.createTable(favoriteWallpapers);
        if (from < 3) await m.createTable(downloadedWallpapers);
        if (from < 4) await m.createTable(blockedTags);
        if (from < 5) await purgePrivateDownloads();
        if (from < 6) await _qualifyWallpapersBySource(m);
      },
    );
  }

  /// Adds the `source` and `page_url` columns to both wallpaper tables and
  /// backfills them.
  ///
  /// Every row written before v6 came from Wallhaven — it was the only source
  /// tela had — so both backfills are facts about the past, not guesses: the
  /// source is the literal `'wallhaven'`, and the page URL is the one
  /// `Wallpaper.pageUrl` used to compose from the id before the model stopped
  /// knowing any site's URL shape. Both are spelled out rather than read from
  /// the code for the same reason [purgePrivateDownloads] hardcodes
  /// `'appPrivate'`: a migration is frozen at the moment it shipped and must
  /// keep writing the value that was really written, whatever the code is
  /// renamed to later.
  ///
  /// [Migrator.alterTable] rather than `addColumn`, because the primary key
  /// changes too — SQLite cannot alter one, so the table is recreated and its
  /// rows copied across.
  Future<void> _qualifyWallpapersBySource(Migrator m) async {
    await _addSourceColumn(m, favoriteWallpapers);
    await _addSourceColumn(m, downloadedWallpapers);
  }

  /// Recreates [table] with its `source` column added, backfilled to
  /// `'wallhaven'`.
  ///
  /// `TableMigration` is drift's experimental API and the only one that can do
  /// this: the alternative is hand-written `CREATE`/`INSERT SELECT`/`DROP` SQL,
  /// which is the same operation with the column list copied out by hand — one
  /// more place for the schema to drift from the tables above.
  Future<void> _addSourceColumn(Migrator m, TableInfo<Table, Object?> table) {
    final GeneratedColumn<Object> source = table.columnsByName['source']!;
    final GeneratedColumn<Object> pageUrl = table.columnsByName['page_url']!;
    return m.alterTable(
      // ignore: experimental_member_use, drift's only recreate-and-copy path
      TableMigration(
        table,
        columnTransformer: <GeneratedColumn<Object>, Expression<Object>>{
          source: const Constant<String>('wallhaven'),
          pageUrl: const CustomExpression<String>(
            "'https://wallhaven.cc/w/' || id",
          ),
        },
        newColumns: <GeneratedColumn<Object>>[source, pageUrl],
      ),
    );
  }

  /// Deletes every app-private download row, wherever it came from.
  ///
  /// Until v5 the history gated on purity alone, so a *safe* wallpaper sent to
  /// the app-private tier — by config, or by the per-download override — earned
  /// a row. Filtering those out on read is not enough to undo it: this
  /// database is backed up (see `backup_rules.xml`, which excludes only the
  /// encrypted API key), so an unpurged row keeps a private file's location and
  /// thumbnails in the user's cloud backup — the exact exposure the tier exists
  /// to prevent. The file itself is never touched, only the index of it.
  ///
  /// The tier is matched as a string literal rather than through `StorageTier`:
  /// a migration is frozen at the moment it shipped, and must keep matching the
  /// value that was really written even if the enum is renamed later.
  Future<void> purgePrivateDownloads() {
    final DeleteStatement<$DownloadedWallpapersTable, DownloadRow> statement =
        delete(downloadedWallpapers)..where(
          ($DownloadedWallpapersTable row) => row.tier.equals('appPrivate'),
        );
    return statement.go();
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

  /// Drops the download row for [ref]. The file it points at is not touched.
  Future<void> deleteDownload(WallpaperRef ref) {
    final DeleteStatement<$DownloadedWallpapersTable, DownloadRow> statement =
        delete(downloadedWallpapers)
          ..where(($DownloadedWallpapersTable row) => _matches(row, ref));
    return statement.go();
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

  /// True when [ref] is currently favorited.
  Future<bool> hasFavorite(WallpaperRef ref) async {
    final SimpleSelectStatement<$FavoriteWallpapersTable, FavoriteRow> query =
        select(favoriteWallpapers)
          ..where(($FavoriteWallpapersTable row) => _matches(row, ref));
    return await query.getSingleOrNull() != null;
  }

  /// Writes one favorite, replacing any earlier row with the same id.
  Future<void> putFavorite(FavoriteWallpapersCompanion row) {
    return into(favoriteWallpapers).insertOnConflictUpdate(row);
  }

  /// Removes one favorite. A no-op when [ref] was never saved.
  Future<void> deleteFavorite(WallpaperRef ref) {
    final DeleteStatement<$FavoriteWallpapersTable, FavoriteRow> statement =
        delete(favoriteWallpapers)
          ..where(($FavoriteWallpapersTable row) => _matches(row, ref));
    return statement.go();
  }

  /// Matches the one row [ref] names, on both halves of the key.
  ///
  /// Shared by every wallpaper-keyed statement: matching on the id alone still
  /// *looks* correct while there is one source, which is exactly how a
  /// half-migrated key survives a test suite.
  static Expression<bool> _matches(WallpaperColumns row, WallpaperRef ref) {
    return row.source.equals(ref.source.value) & row.id.equals(ref.id);
  }

  /// Every blocked tag, most recently blocked first.
  Future<List<BlockedTagRow>> blockedTagRows() {
    final SimpleSelectStatement<$BlockedTagsTable, BlockedTagRow> query =
        select(blockedTags)..orderBy(<OrderClauseGenerator<$BlockedTagsTable>>[
          ($BlockedTagsTable row) => OrderingTerm.desc(row.blockedAt),
        ]);
    return query.get();
  }

  /// Writes one blocked tag, replacing any earlier block of the same id.
  Future<void> putBlockedTag(BlockedTagsCompanion row) {
    return into(blockedTags).insertOnConflictUpdate(row);
  }

  /// Unblocks one tag. A no-op when [id] was never blocked.
  Future<void> deleteBlockedTag(int id) {
    final DeleteStatement<$BlockedTagsTable, BlockedTagRow> statement = delete(
      blockedTags,
    )..where(($BlockedTagsTable row) => row.id.equals(id));
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
