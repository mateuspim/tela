import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/data/downloads/drift_download_history.dart';
import 'package:tela/data/favorites/drift_favorites_repository.dart';
import 'package:tela/data/settings/drift_settings_repository.dart';
import 'package:tela/data/tag_blocklist/drift_tag_blocklist_repository.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';

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
      'v1 → v5 adds every new table without touching saved settings',
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

    test('v2 → v5 adds downloads and blocked tags, keeps favorites', () async {
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

    test('v3 → v5 adds blocked tags and keeps the download history', () async {
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

    test('v3 → v5 purges the app-private rows, not just hides them', () async {
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

    test('a fresh install creates every table', () async {
      final TelaDatabase db = TelaDatabase(NativeDatabase(file));

      expect(await DriftFavoritesRepository(db).favorites(), isEmpty);
      expect(await DriftDownloadHistory(db).downloads(), isEmpty);
      expect(await DriftTagBlocklistRepository(db).all(), isEmpty);
      expect(
        await DriftSettingsRepository(db).loadStorageSettings(),
        StorageSettings.defaults,
      );

      await db.close();
    });
  });
}
