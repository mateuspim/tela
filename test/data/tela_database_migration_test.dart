import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/data/downloads/drift_download_history.dart';
import 'package:tela/data/favorites/drift_favorites_repository.dart';
import 'package:tela/data/settings/drift_settings_repository.dart';
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
      'v1 → v3 adds the new tables without touching saved settings',
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

        await db.close();
      },
    );

    test('v2 → v3 adds downloads and keeps the favorites shelf', () async {
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
      expect(
        (await DriftSettingsRepository(db).loadStorageSettings()).sfwTier,
        StorageTier.appPrivate,
      );

      await db.close();
    });

    test('a fresh install creates every table', () async {
      final TelaDatabase db = TelaDatabase(NativeDatabase(file));

      expect(await DriftFavoritesRepository(db).favorites(), isEmpty);
      expect(await DriftDownloadHistory(db).downloads(), isEmpty);
      expect(
        await DriftSettingsRepository(db).loadStorageSettings(),
        StorageSettings.defaults,
      );

      await db.close();
    });
  });
}
