import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/data/favorites/drift_favorites_repository.dart';
import 'package:tela/data/settings/drift_settings_repository.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';

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

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tela_migration');
    file = File('${dir.path}/tela.sqlite');
  });

  tearDown(() => dir.delete(recursive: true));

  group('TelaDatabase migration', () {
    test('v1 → v2 adds favorites without touching saved settings', () async {
      // The device carries a real API key and real download destinations. A
      // migration that recreates the database instead of altering it presents
      // as "the app forgot my settings" — the exact bug 91cb7b0 chased down.
      _createV1(file);

      final TelaDatabase db = TelaDatabase(NativeDatabase(file));
      final DriftSettingsRepository settings = DriftSettingsRepository(db);
      final DriftFavoritesRepository favorites = DriftFavoritesRepository(db);

      final StorageSettings loaded = await settings.loadStorageSettings();
      expect(
        loaded.sfwTier,
        StorageTier.appPrivate,
        reason: 'the v1 setting must survive the upgrade',
      );
      expect(
        await favorites.favorites(),
        isEmpty,
        reason: 'the favorites table must exist and start empty',
      );

      await db.close();
    });

    test('a fresh install creates both tables', () async {
      final TelaDatabase db = TelaDatabase(NativeDatabase(file));
      final DriftFavoritesRepository favorites = DriftFavoritesRepository(db);

      expect(await favorites.favorites(), isEmpty);
      expect(
        await DriftSettingsRepository(db).loadStorageSettings(),
        StorageSettings.defaults,
      );

      await db.close();
    });
  });
}
