import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:tela/data/db/tela_tables.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

part 'tela_database.g.dart';

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
    DownloadQueueEntries,
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
  int get schemaVersion => 8;

  /// Adds tables to an existing database instead of recreating it.
  ///
  /// The settings table shipped at v1 with real user choices in it, favorites
  /// at v2, and downloads at v3. A blocked-tags table arriving at v4 must not
  /// cost anyone either — each version only ever adds what the one before it
  /// lacked. v5 is the exception that proves the shape: it adds nothing and
  /// *removes* rows, because those rows should never have been written. v6 is
  /// the other exception: it rewrites two tables, and every row they hold is
  /// kept. v7 is back to the ordinary shape — one new table, the download
  /// queue, and nothing existing touched. v8 is the same shape again, one step
  /// smaller: a nullable `tag` column on the two download tables. Every
  /// existing row reads back untagged, which is what it is — the files were
  /// written before tags existed and sit in their tier's root.
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
        if (from < 7) await m.createTable(downloadQueueEntries);
        // Only for a table this upgrade did not already build from today's
        // definition — and "build" includes **rewriting**. Both `createTable`
        // and v6's `alterTable` emit the current schema, tag column included,
        // so a database coming through either of those steps arrives at v8
        // already holding the column, and `ADD COLUMN` would fail the whole
        // migration with "duplicate column name".
        //
        // The cutoffs are therefore the last version that *touched* each table,
        // not the version that introduced it: downloads were rewritten at v6
        // (not merely created at v3), and the queue was created at v7. Any
        // later column-add owes the same reasoning, against whatever the
        // migrations do by then.
        if (from < 8) {
          if (from >= 6) {
            await m.addColumn(downloadedWallpapers, downloadedWallpapers.tag);
          }
          if (from >= 7) {
            await m.addColumn(downloadQueueEntries, downloadQueueEntries.tag);
          }
        }
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

  /// Re-points [ref]'s row at a file that has moved into another tag folder.
  ///
  /// Location and tag are written **together**, in one statement, because they
  /// are one fact: a tag is a directory, so a row holding the new tag beside
  /// the old path describes a file that is not there. Nothing else on the row
  /// changes — the wallpaper did not change, only where it is filed.
  Future<void> retagDownload(WallpaperRef ref, String location, String? tag) {
    final UpdateStatement<$DownloadedWallpapersTable, DownloadRow> statement =
        update(downloadedWallpapers)
          ..where(($DownloadedWallpapersTable row) => _matches(row, ref));
    return statement.write(
      DownloadedWallpapersCompanion(
        location: Value<String>(location),
        tag: Value<String?>(tag),
      ),
    );
  }

  /// Re-points [ref]'s row at a file now in [tier], at [location], under [tag].
  ///
  /// [retagDownload] plus the tier, in one statement for the same reason those
  /// two are: a delete routes by the tier column, so a row carrying the new
  /// path beside the old tier describes a file nothing can reach.
  Future<void> relocateDownload(
    WallpaperRef ref,
    String tier,
    String location,
    String? tag,
  ) {
    final UpdateStatement<$DownloadedWallpapersTable, DownloadRow> statement =
        update(downloadedWallpapers)
          ..where(($DownloadedWallpapersTable row) => _matches(row, ref));
    return statement.write(
      DownloadedWallpapersCompanion(
        tier: Value<String>(tier),
        location: Value<String>(location),
        tag: Value<String?>(tag),
      ),
    );
  }

  /// Drops the download row for [ref]. The file it points at is not touched.
  Future<void> deleteDownload(WallpaperRef ref) {
    final DeleteStatement<$DownloadedWallpapersTable, DownloadRow> statement =
        delete(downloadedWallpapers)
          ..where(($DownloadedWallpapersTable row) => _matches(row, ref));
    return statement.go();
  }

  /// Drops every download row named in [refs] — one statement per distinct
  /// source, an `id IN (...)` rather than a query per row.
  ///
  /// A stale-history cleanup ticks every row whose file is already gone, and
  /// that can run into the hundreds; [deleteDownload] in a loop paid one
  /// round trip per row for it, which was the whole five seconds a cleanup of
  /// 601 rows visibly stalled on (owner, on device, 2026-07-29). Grouped by
  /// source because [_matches] must not compare an id across sources, and
  /// [SourceId] admits few enough values that this is at most a handful of
  /// statements even for a history that spans every one of them.
  Future<void> deleteDownloads(Iterable<WallpaperRef> refs) async {
    final Map<SourceId, List<String>> idsBySource = <SourceId, List<String>>{};
    for (final WallpaperRef ref in refs) {
      (idsBySource[ref.source] ??= <String>[]).add(ref.id);
    }
    if (idsBySource.isEmpty) return;
    await batch((Batch batch) {
      for (final MapEntry<SourceId, List<String>> entry
          in idsBySource.entries) {
        batch.deleteWhere(
          downloadedWallpapers,
          ($DownloadedWallpapersTable row) =>
              row.source.equals(entry.key.value) & row.id.isIn(entry.value),
        );
      }
    });
  }

  /// Every queue entry, oldest first — a queue is a line.
  Future<List<QueueRow>> queueRows() {
    final SimpleSelectStatement<$DownloadQueueEntriesTable, QueueRow> query =
        select(downloadQueueEntries)
          ..orderBy(<OrderClauseGenerator<$DownloadQueueEntriesTable>>[
            ($DownloadQueueEntriesTable row) => OrderingTerm.asc(row.queuedAt),
          ]);
    return query.get();
  }

  /// Adds one entry, **leaving any existing entry for the same wallpaper
  /// exactly as it was**.
  ///
  /// `insertOrIgnore`, not the `insertOnConflictUpdate` the other tables use:
  /// an entry that is already running or has already failed twice must not be
  /// reset to a fresh pending row just because the user ticked the same shelf
  /// again. That is what makes enqueuing idempotent.
  Future<void> addQueueEntry(DownloadQueueEntriesCompanion row) {
    return into(
      downloadQueueEntries,
    ).insert(row, mode: InsertMode.insertOrIgnore);
  }

  /// Takes the oldest pending entry and marks it running, or null when there
  /// is none.
  ///
  /// In one transaction because several workers drain at once: a select
  /// followed by a separate update lets two of them read the same row before
  /// either writes, and the user gets the same wallpaper downloaded twice.
  Future<QueueRow?> claimNextQueueRow(String pending, String running) {
    return transaction(() async {
      final QueueRow? next = await _oldestQueueRow(pending);
      if (next == null) return null;
      await _writeQueueState(
        WallpaperRef(SourceId(next.source), next.id),
        DownloadQueueEntriesCompanion(
          state: Value<String>(running),
          attempts: Value<int>(next.attempts + 1),
        ),
      );
      return next.copyWith(state: running, attempts: next.attempts + 1);
    });
  }

  Future<QueueRow?> _oldestQueueRow(String state) {
    final SimpleSelectStatement<$DownloadQueueEntriesTable, QueueRow> query =
        select(downloadQueueEntries)
          ..where(
            ($DownloadQueueEntriesTable row) => row.state.equals(state),
          )
          ..orderBy(<OrderClauseGenerator<$DownloadQueueEntriesTable>>[
            ($DownloadQueueEntriesTable row) => OrderingTerm.asc(row.queuedAt),
          ])
          ..limit(1);
    return query.getSingleOrNull();
  }

  /// Marks [ref] failed for [failure], keeping it in the queue.
  Future<void> failQueueEntry(WallpaperRef ref, String state, String failure) {
    return _writeQueueState(
      ref,
      DownloadQueueEntriesCompanion(
        state: Value<String>(state),
        failure: Value<String>(failure),
      ),
    );
  }

  /// Puts [ref] back to pending and clears its failure, keeping its attempt
  /// count — a wallpaper that has failed three times should still look like it.
  Future<void> requeueQueueEntry(WallpaperRef ref, String pending) {
    return _writeQueueState(
      ref,
      DownloadQueueEntriesCompanion(
        state: Value<String>(pending),
        failure: const Value<String?>(null),
      ),
    );
  }

  /// Moves every entry in [from] to [to], answering how many moved.
  ///
  /// Serves both the retry-all-failed button and the startup demotion of
  /// entries a killed process left marked running.
  Future<int> moveQueueEntries(String from, String to) {
    final UpdateStatement<$DownloadQueueEntriesTable, QueueRow> statement =
        update(downloadQueueEntries)
          ..where(($DownloadQueueEntriesTable row) => row.state.equals(from));
    return statement.write(
      DownloadQueueEntriesCompanion(
        state: Value<String>(to),
        failure: const Value<String?>(null),
      ),
    );
  }

  /// Changes the explicit destination of work that is not already writing.
  Future<int> rerouteQueueEntries(String from, String to, String running) {
    final UpdateStatement<$DownloadQueueEntriesTable, QueueRow> statement =
        update(downloadQueueEntries)..where(
          ($DownloadQueueEntriesTable row) =>
              row.tier.equals(from) & row.state.equals(running).not(),
        );
    return statement.write(
      DownloadQueueEntriesCompanion(tier: Value<String>(to)),
    );
  }

  Future<void> _writeQueueState(
    WallpaperRef ref,
    DownloadQueueEntriesCompanion fields,
  ) async {
    final UpdateStatement<$DownloadQueueEntriesTable, QueueRow> statement =
        update(downloadQueueEntries)
          ..where(($DownloadQueueEntriesTable row) => _matches(row, ref));
    await statement.write(fields);
  }

  /// Drops one queue entry. Nothing already written to disk is touched.
  Future<void> deleteQueueEntry(WallpaperRef ref) {
    final DeleteStatement<$DownloadQueueEntriesTable, QueueRow> statement =
        delete(downloadQueueEntries)
          ..where(($DownloadQueueEntriesTable row) => _matches(row, ref));
    return statement.go();
  }

  /// Empties the queue.
  Future<void> clearQueue() => delete(downloadQueueEntries).go();

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
