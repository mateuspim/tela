import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/data/settings/drift_settings_repository.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';

void main() {
  late TelaDatabase db;
  late DriftSettingsRepository settings;

  setUp(() {
    db = TelaDatabase(NativeDatabase.memory());
    settings = DriftSettingsRepository(db);
  });

  tearDown(() => db.close());

  group('DriftSettingsRepository', () {
    test('returns the domain defaults before anything is saved', () async {
      expect(await settings.loadStorageSettings(), StorageSettings.defaults);
    });

    test('round-trips saved settings', () async {
      final StorageSettings saved = StorageSettings(
        sfwTier: StorageTier.appPrivate,
        nsfwTier: StorageTier.filesOutsideGallery,
      );

      await settings.saveStorageSettings(saved);

      expect(await settings.loadStorageSettings(), saved);
    });

    test('overwrites rather than accumulating rows', () async {
      await settings.saveStorageSettings(
        StorageSettings.defaults.copyWith(sfwTier: StorageTier.appPrivate),
      );
      await settings.saveStorageSettings(
        StorageSettings.defaults.copyWith(
          sfwTier: StorageTier.filesOutsideGallery,
        ),
      );

      final StorageSettings loaded = await settings.loadStorageSettings();
      expect(loaded.sfwTier, StorageTier.filesOutsideGallery);
    });

    test('falls back to the default when a stored tier is unknown', () async {
      await db.putSetting('storage.tier.sfw', 'dropbox');

      final StorageSettings loaded = await settings.loadStorageSettings();

      expect(loaded.sfwTier, StorageSettings.defaults.sfwTier);
    });

    test('refuses a stored nsfw tier that would index the file', () async {
      await db.putSetting('storage.tier.nsfw', StorageTier.sharedGallery.name);

      final StorageSettings loaded = await settings.loadStorageSettings();

      expect(loaded.nsfwTier, StorageTier.appPrivate);
    });

    test('leaves the private library unlocked until it is asked for', () async {
      expect(await settings.isPrivateLibraryLocked(), isFalse);
    });

    test('round-trips the private library lock', () async {
      await settings.setPrivateLibraryLocked(locked: true);
      expect(await settings.isPrivateLibraryLocked(), isTrue);

      await settings.setPrivateLibraryLocked(locked: false);
      expect(await settings.isPrivateLibraryLocked(), isFalse);
    });

    test('reads a corrupt lock setting as locked', () async {
      // Unlike the tier fallbacks, this one fails closed: "I can't tell whether
      // this was locked" has only one safe reading.
      await db.putSetting('privacy.privateLibraryLock', 'maybe');

      expect(await settings.isPrivateLibraryLocked(), isTrue);
    });
  });
}
