import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/data/downloads/drift_download_history.dart';
import 'package:tela/data/downloads/drift_download_queue.dart';
import 'package:tela/data/favorites/drift_favorites_repository.dart';
import 'package:tela/data/settings/drift_settings_repository.dart';
import 'package:tela/data/tag_blocklist/drift_tag_blocklist_repository.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/queued_download.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

/// The v1 schema, exactly as it shipped: settings only, no favorites.
///
/// Written by hand because drift can only ever *create* the current schema, and
/// what needs proving is the upgrade path a phone with real data will take.
void _createV1(File file) {
  sqlite3.open(file.path)
    ..execute(
      'CREATE TABLE setting_entries (key TEXT NOT NULL, '
      'value TEXT NOT NULL, PRIMARY KEY (key));',
    )
    ..execute(
      'INSERT INTO setting_entries (key, value) '
      "VALUES ('storage.tier.sfw', 'appPrivate');",
    )
    ..execute('PRAGMA user_version = 1;')
    ..dispose();
}

/// The v2 schema, exactly as it shipped: settings plus favorites, no downloads.
///
/// Carries one real favorite, because the thing this proves is that a device
/// arriving at v3 keeps the shelf it already had.
void _createV2(File file) {
  _createV1(file);
  sqlite3.open(file.path)
    ..execute(
      'CREATE TABLE favorite_wallpapers ( '
      'id TEXT NOT NULL, full_image_url TEXT NOT NULL, '
      'thumb_small_url TEXT NOT NULL, thumb_large_url TEXT NOT NULL, '
      'thumb_original_url TEXT NOT NULL, width INTEGER NOT NULL, '
      'height INTEGER NOT NULL, file_size_bytes INTEGER NOT NULL, '
      'purity TEXT NOT NULL, category TEXT NOT NULL, colors TEXT NOT NULL, '
      'saved_at INTEGER NOT NULL, PRIMARY KEY (id));',
    )
    ..execute(
      'INSERT INTO favorite_wallpapers VALUES ( '
      "'e7jvjd', 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg', "
      "'https://th.wallhaven.cc/small/e7/e7jvjd.jpg', "
      "'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg', "
      "'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg', "
      "1080, 2400, 1024, 'sfw', 'general', '#660000', 1767225600);",
    )
    ..execute('PRAGMA user_version = 2;')
    ..dispose();
}

/// The v3 schema, exactly as it shipped: settings, favorites, and downloads —
/// no blocked tags.
///
/// Carries two real downloads, for the same reason [_createV2] carries a real
/// favorite: what needs proving is what a device arriving at v5 keeps and what
/// it loses. One went to the gallery and must survive. The other is the bug
/// itself — a **safe** wallpaper sent to the app-private tier, which v3 happily
/// recorded because it only ever gated on purity. v5 must purge that one.
void _createV3(File file) {
  _createV2(file);
  sqlite3.open(file.path)
    ..execute(
      'CREATE TABLE downloaded_wallpapers ( '
      'id TEXT NOT NULL, full_image_url TEXT NOT NULL, '
      'thumb_small_url TEXT NOT NULL, thumb_large_url TEXT NOT NULL, '
      'thumb_original_url TEXT NOT NULL, width INTEGER NOT NULL, '
      'height INTEGER NOT NULL, file_size_bytes INTEGER NOT NULL, '
      'purity TEXT NOT NULL, category TEXT NOT NULL, colors TEXT NOT NULL, '
      'tier TEXT NOT NULL, location TEXT NOT NULL, '
      'downloaded_at INTEGER NOT NULL, PRIMARY KEY (id));',
    )
    ..execute(
      'INSERT INTO downloaded_wallpapers VALUES ( '
      "'e7jvjd', 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg', "
      "'https://th.wallhaven.cc/small/e7/e7jvjd.jpg', "
      "'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg', "
      "'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg', "
      "1080, 2400, 1024, 'sfw', 'general', '#660000', "
      "'sharedGallery', 'content://media/e7jvjd', 1767225600);",
    )
    ..execute(
      'INSERT INTO downloaded_wallpapers VALUES ( '
      "'7j1mzo', 'https://w.wallhaven.cc/full/7j/wallhaven-7j1mzo.jpg', "
      "'https://th.wallhaven.cc/small/7j/7j1mzo.jpg', "
      "'https://th.wallhaven.cc/lg/7j/7j1mzo.jpg', "
      "'https://th.wallhaven.cc/orig/7j/7j1mzo.jpg', "
      "1080, 2400, 1024, 'sfw', 'general', '#660000', "
      "'appPrivate', 'file:///data/tela/7j1mzo.jpg', 1767225600);",
    )
    ..execute('PRAGMA user_version = 3;')
    ..dispose();
}

/// The v5 schema, exactly as it shipped: every table, and no `source` column.
///
/// This is the state a device that installed the last release is really in, so
/// it is the upgrade v6 has to survive. The app-private download is dropped
/// rather than carried, because a real v5 device already had it purged — v6's
/// upgrade never re-runs that purge.
void _createV5(File file) {
  _createV3(file);
  sqlite3.open(file.path)
    ..execute(
      'CREATE TABLE blocked_tags ( '
      'id INTEGER NOT NULL, name TEXT NOT NULL, '
      'blocked_at INTEGER NOT NULL, PRIMARY KEY (id));',
    )
    ..execute("DELETE FROM downloaded_wallpapers WHERE tier = 'appPrivate';")
    ..execute('PRAGMA user_version = 5;')
    ..dispose();
}

/// The v6 schema, exactly as it shipped: every table qualified by source, and
/// no download queue.
///
/// This is the state a device that installed the last release is really in, so
/// it is the upgrade v7 has to survive. Built by running the real v5 → v6
/// migration rather than by hand: v6 *recreates* both wallpaper tables through
/// drift's `TableMigration`, and a hand-written copy of the result would be a
/// second definition of the schema free to disagree with the first.
Future<void> _createV6(File file) async {
  _createV5(file);
  final TelaDatabase db = TelaDatabase(NativeDatabase(file));
  // Any read forces the migration to run; the row count is incidental.
  await db.favoriteRows();
  await db.close();
  // Everything the versions *after* v6 added has to come back off, because
  // opening the database above ran the whole chain, not just v5 → v6. The queue
  // table goes whole; v8's `tag` columns are dropped individually, and the
  // queue's goes with its table. Each later migration adds one line here — the
  // price of building this state by running the real thing rather than by
  // hand-copying a schema that would then be free to disagree with it.
  sqlite3.open(file.path)
    ..execute('DROP TABLE IF EXISTS download_queue_entries;')
    ..execute('ALTER TABLE downloaded_wallpapers DROP COLUMN tag;')
    ..execute('PRAGMA user_version = 6;')
    ..dispose();
}

/// The v7 schema: v6 plus the download queue, and no tag columns.
///
/// Built the way [_createV6] is and for the same reason — by running the real
/// migrations and then unwinding what came after — rather than by hand-copying
/// a schema that would be free to disagree with the one the app ships.
Future<void> _createV7(File file) async {
  await _createV6(file);
  final TelaDatabase db = TelaDatabase(NativeDatabase(file));
  // A real queued entry, so the v8 upgrade has something to keep: a column
  // added to an empty table proves only that the statement ran.
  await DriftDownloadQueue(db).enqueue(<QueuedDownload>[
    QueuedDownload(
      wallpaper: _wallpaperFrom(SourceId.konachan, '12345'),
      queuedAt: DateTime(2026, 8, 12),
    ),
  ]);
  await db.close();
  sqlite3.open(file.path)
    ..execute('ALTER TABLE downloaded_wallpapers DROP COLUMN tag;')
    ..execute('ALTER TABLE download_queue_entries DROP COLUMN tag;')
    ..execute('PRAGMA user_version = 7;')
    ..dispose();
}

/// Whether [table] has a column called [column].
bool _hasColumn(File file, String table, String column) {
  final Database db = sqlite3.open(file.path);
  final ResultSet rows = db.select('PRAGMA table_info($table);');
  final bool found = rows.any((Row row) => row['name'] == column);
  db.dispose();
  return found;
}

/// Whether [table] exists in the file at all.
bool _hasTable(File file, String table) {
  final Database db = sqlite3.open(file.path);
  final ResultSet rows = db.select(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?;",
    <Object>[table],
  );
  final bool found = rows.isNotEmpty;
  db.dispose();
  return found;
}

/// Reads one column of one table straight out of SQLite.
List<String> _rawColumn(File file, String table, String column) {
  final Database db = sqlite3.open(file.path);
  final ResultSet rows = db.select('SELECT $column FROM $table;');
  final List<String> values = rows
      .map((Row row) => row[column] as String)
      .toList(growable: false);
  db.dispose();
  return values;
}

/// Reads the download rows straight out of SQLite, past the adapter's filter.
///
/// The filter would hide a purged row and an unpurged one alike, so proving
/// the migration actually *deleted* anything means asking the file itself —
/// which is the copy that ends up in the user's cloud backup.
List<String> _rawDownloadIds(File file) {
  final Database db = sqlite3.open(file.path);
  final ResultSet rows = db.select('SELECT id FROM downloaded_wallpapers;');
  final List<String> ids = rows
      .map((Row row) => row['id'] as String)
      .toList(growable: false);
  db.dispose();
  return ids;
}

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tela_migration');
    file = File('${dir.path}/tela.sqlite');
  });

  tearDown(() => dir.delete(recursive: true));

  group('TelaDatabase migration', () {
    test(
      'v1 → v6 adds every new table without touching saved settings',
      () async {
        // The device carries a real API key and real download destinations. A
        // migration that recreates the database instead of altering it presents
        // as "the app forgot my settings" — the exact bug 91cb7b0 chased down.
        _createV1(file);

        final TelaDatabase db = TelaDatabase(NativeDatabase(file));
        final DriftSettingsRepository settings = DriftSettingsRepository(db);

        final StorageSettings loaded = await settings.loadStorageSettings();
        expect(
          loaded.sfwTier,
          StorageTier.appPrivate,
          reason: 'the v1 setting must survive the upgrade',
        );
        expect(
          await DriftFavoritesRepository(db).favorites(),
          isEmpty,
          reason: 'the favorites table must exist and start empty',
        );
        expect(
          await DriftDownloadHistory(db).downloads(),
          isEmpty,
          reason: 'the downloads table must exist and start empty',
        );
        expect(
          await DriftTagBlocklistRepository(db).all(),
          isEmpty,
          reason: 'the blocked-tags table must exist and start empty',
        );

        await db.close();
      },
    );

    test('v2 → v6 adds downloads and blocked tags, keeps favorites', () async {
      _createV2(file);

      final TelaDatabase db = TelaDatabase(NativeDatabase(file));

      final List<Wallpaper> favorites = await DriftFavoritesRepository(
        db,
      ).favorites();
      expect(
        favorites.single.id,
        'e7jvjd',
        reason: 'a v2 favorite must survive the upgrade',
      );
      expect(await DriftDownloadHistory(db).downloads(), isEmpty);
      expect(await DriftTagBlocklistRepository(db).all(), isEmpty);
      expect(
        (await DriftSettingsRepository(db).loadStorageSettings()).sfwTier,
        StorageTier.appPrivate,
      );

      await db.close();
    });

    test('v3 → v6 adds blocked tags and keeps the download history', () async {
      _createV3(file);

      final TelaDatabase db = TelaDatabase(NativeDatabase(file));

      final List<DownloadRecord> downloads = await DriftDownloadHistory(
        db,
      ).downloads();
      expect(
        downloads.single.wallpaper.id,
        'e7jvjd',
        reason: 'a v3 download to the gallery must survive the upgrade',
      );
      expect(await DriftTagBlocklistRepository(db).all(), isEmpty);

      await db.close();
    });

    test('v3 → v6 purges the app-private rows, not just hides them', () async {
      _createV3(file);
      expect(
        _rawDownloadIds(file),
        containsAll(<String>['e7jvjd', '7j1mzo']),
        reason: 'v3 recorded the private download; that is the bug',
      );

      final TelaDatabase db = TelaDatabase(NativeDatabase(file));
      // Touch the history so the migration has certainly run.
      await DriftDownloadHistory(db).downloads();
      await db.close();

      // Gone from the file, not merely filtered out of the listing: the row is
      // what gets backed up, so hiding it would leave the exposure in place.
      expect(_rawDownloadIds(file), <String>['e7jvjd']);
    });

    test('v5 → v6 keeps every row and attributes it to Wallhaven', () async {
      // Wallhaven was the only source there was, so the backfill is a fact
      // about the past, not a guess. A migration that dropped these rows would
      // present as "the app forgot my favorites" — the one thing an offline
      // library exists to survive.
      _createV5(file);

      final TelaDatabase db = TelaDatabase(NativeDatabase(file));

      final List<Wallpaper> favorites = await DriftFavoritesRepository(
        db,
      ).favorites();
      expect(favorites.single.ref, _wallhaven('e7jvjd'));
      expect(
        favorites.single.pageUrl,
        Uri.parse('https://wallhaven.cc/w/e7jvjd'),
      );
      final List<DownloadRecord> downloads = await DriftDownloadHistory(
        db,
      ).downloads();
      expect(downloads.single.wallpaper.ref, _wallhaven('e7jvjd'));
      // Asked of the row itself, not of the mapper: a `storedSource` that
      // defaults to Wallhaven would answer the same on an unwritten column.
      expect(await db.hasFavorite(_wallhaven('e7jvjd')), isTrue);

      await db.close();

      expect(_rawColumn(file, 'favorite_wallpapers', 'source'), <String>[
        'wallhaven',
      ]);
      // The permalink the model used to compose from the id, now a column —
      // a row that lost it would have no "View on Wallhaven" offline.
      expect(_rawColumn(file, 'favorite_wallpapers', 'page_url'), <String>[
        'https://wallhaven.cc/w/e7jvjd',
      ]);
      expect(_rawColumn(file, 'downloaded_wallpapers', 'source'), <String>[
        'wallhaven',
      ]);
    });

    test('v6 keys on the source too, so two sites cannot collide', () async {
      // The reason the column exists: Konachan #12345 and yande.re #12345 are
      // two wallpapers, and the old id-only key would have kept one.
      _createV5(file);
      final TelaDatabase db = TelaDatabase(NativeDatabase(file));
      final DriftFavoritesRepository favorites = DriftFavoritesRepository(db);

      await favorites.save(_wallpaperFrom(SourceId.konachan, '12345'));
      await favorites.save(_wallpaperFrom(const SourceId('yandere'), '12345'));

      expect(await favorites.favorites(), hasLength(3));
      await favorites.forget(
        const WallpaperRef(SourceId.konachan, '12345'),
      );
      expect(
        (await favorites.favorites()).map((Wallpaper w) => w.ref),
        containsAll(<WallpaperRef>[
          const WallpaperRef(SourceId('yandere'), '12345'),
          _wallhaven('e7jvjd'),
        ]),
      );

      await db.close();
    });

    test('v6 → v7 adds the download queue and keeps every row', () async {
      // v7 is an ordinary additive step: one new table, nothing existing
      // touched. What it must not do is cost the device the library it has —
      // the same claim every version before it had to make.
      await _createV6(file);
      expect(_hasTable(file, 'download_queue_entries'), isFalse);

      final TelaDatabase db = TelaDatabase(NativeDatabase(file));

      expect(await DriftDownloadQueue(db).entries(), isEmpty);
      expect(
        (await DriftFavoritesRepository(db).favorites()).single.ref,
        _wallhaven('e7jvjd'),
      );
      expect(
        (await DriftDownloadHistory(db).downloads()).single.wallpaper.ref,
        _wallhaven('e7jvjd'),
      );

      await db.close();

      expect(_hasTable(file, 'download_queue_entries'), isTrue);
    });

    test('v7 → v8 tags the download tables and keeps every row', () async {
      // v8 is the ordinary shape again: one nullable column on two tables.
      // Every row that existed reads back untagged, which is the truth about
      // it — those files were written before tags and sit in their tier's root.
      await _createV7(file);
      expect(_hasColumn(file, 'downloaded_wallpapers', 'tag'), isFalse);

      final TelaDatabase db = TelaDatabase(NativeDatabase(file));

      final DownloadRecord kept = (await DriftDownloadHistory(
        db,
      ).downloads()).single;
      expect(kept.wallpaper.ref, _wallhaven('e7jvjd'));
      expect(kept.tag, isNull);
      expect((await DriftDownloadQueue(db).entries()).single.tag, isNull);

      await db.close();

      expect(_hasColumn(file, 'downloaded_wallpapers', 'tag'), isTrue);
      expect(_hasColumn(file, 'download_queue_entries', 'tag'), isTrue);
    });

    /// The upgrade that nearly shipped broken, and the reason the v8 step is
    /// guarded by version rather than run unconditionally.
    ///
    /// `createTable` and v6's `alterTable` both emit **today's** definition, so
    /// a database old enough to have the downloads table rebuilt on the way
    /// through arrives at v8 already carrying the column — and a second
    /// `ADD COLUMN` fails the entire migration, taking the user's library with
    /// it. Every starting version has to reach v8 once and land in the same
    /// place.
    test('every version from v1 upward reaches v8 exactly once', () async {
      for (final (int version, Future<void> Function(File) build)
          in <(int, Future<void> Function(File))>[
            (1, (File f) async => _createV1(f)),
            (2, (File f) async => _createV2(f)),
            (3, (File f) async => _createV3(f)),
            (5, (File f) async => _createV5(f)),
            (6, _createV6),
            (7, _createV7),
          ]) {
        final File each = File('${file.path}.v$version');
        if (each.existsSync()) each.deleteSync();
        await build(each);

        final TelaDatabase db = TelaDatabase(NativeDatabase(each));
        await db.favoriteRows(); // any read forces the upgrade
        await db.close();

        expect(
          _hasColumn(each, 'downloaded_wallpapers', 'tag'),
          isTrue,
          reason: 'v$version did not reach v8',
        );
        expect(
          _hasColumn(each, 'download_queue_entries', 'tag'),
          isTrue,
          reason: 'v$version did not reach v8',
        );
        each.deleteSync();
      }
    });

    test('a queue written at v7 survives being reopened', () async {
      // The whole point of a durable queue: the process that filled it is gone
      // and the line is still there. This is that, at the file level.
      await _createV6(file);
      final TelaDatabase first = TelaDatabase(NativeDatabase(file));
      await DriftDownloadQueue(first).enqueue(<QueuedDownload>[
        QueuedDownload(
          wallpaper: _wallpaperFrom(SourceId.konachan, '12345'),
          queuedAt: DateTime.utc(2026, 7, 26),
        ),
      ]);
      await first.close();

      final TelaDatabase second = TelaDatabase(NativeDatabase(file));
      final List<QueuedDownload> entries = await DriftDownloadQueue(
        second,
      ).entries();

      expect(
        entries.single.ref,
        const WallpaperRef(SourceId.konachan, '12345'),
      );
      await second.close();
    });

    test('a fresh install creates every table', () async {
      final TelaDatabase db = TelaDatabase(NativeDatabase(file));

      expect(await DriftFavoritesRepository(db).favorites(), isEmpty);
      expect(await DriftDownloadHistory(db).downloads(), isEmpty);
      expect(await DriftDownloadQueue(db).entries(), isEmpty);
      expect(await DriftTagBlocklistRepository(db).all(), isEmpty);
      expect(
        await DriftSettingsRepository(db).loadStorageSettings(),
        StorageSettings.defaults,
      );

      await db.close();
    });
  });
}

/// A Wallhaven ref, the shape every pre-v6 row is expected to carry.
WallpaperRef _wallhaven(String id) => WallpaperRef(SourceId.wallhaven, id);

/// A wallpaper from [source], for the collision the composite key prevents.
Wallpaper _wallpaperFrom(SourceId source, String id) => Wallpaper(
  id: id,
  source: source,
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
  fullImageUrl: 'https://example.test/full/$id.jpg',
  thumbSmallUrl: 'https://example.test/small/$id.jpg',
  thumbLargeUrl: 'https://example.test/lg/$id.jpg',
  thumbOriginalUrl: 'https://example.test/orig/$id.jpg',
  resolution: const Resolution(1080, 2400),
  fileSizeBytes: 1024,
  purity: Purity.sfw,
  category: Category.anime,
  colors: const <String>[],
);
