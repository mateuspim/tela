import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/data/settings/drift_settings_repository.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper_color.dart';

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

  group('DriftSettingsRepository account defaults', () {
    test('answers null before a key was ever saved', () async {
      expect(await settings.loadAccountDefaults(), isNull);
    });

    test('round-trips the synced defaults', () async {
      await settings.saveAccountDefaults(_account);

      expect(await settings.loadAccountDefaults(), _account);
    });

    test("stores them as Wallhaven's own literals", () async {
      await settings.saveAccountDefaults(_account);

      expect(await db.settingValue('account.categories'), '010');
      expect(await db.settingValue('account.topRange'), '1w');
    });

    test('never stores a purity — the account does not get to decide that, '
        'and a row nothing reads is a row that misleads', () async {
      await settings.saveAccountDefaults(_account);

      expect(await db.settingValue('account.purity'), isNull);
    });

    test('a re-sync drops the purity row an older build left behind', () async {
      await db.putSetting('account.purity', '111');

      await settings.saveAccountDefaults(_account);

      expect(await db.settingValue('account.purity'), isNull);
    });

    test('a re-sync overwrites rather than accumulating rows', () async {
      await settings.saveAccountDefaults(_account);
      await settings.saveAccountDefaults(
        const AccountSettings(
          categories: CategoryFilter.all,
          topRange: TopRange.oneYear,
        ),
      );

      final AccountSettings? loaded = await settings.loadAccountDefaults();
      expect(loaded?.categories.toApiBits(), '111');
      expect(loaded?.topRange, TopRange.oneYear);
    });

    test('forgetting the key removes every row of them, including the one an '
        'older build wrote', () async {
      await settings.saveAccountDefaults(_account);
      await db.putSetting('account.purity', '111');

      await settings.forgetAccountDefaults();

      expect(await settings.loadAccountDefaults(), isNull);
      expect(await db.settingValue('account.categories'), isNull);
      expect(await db.settingValue('account.topRange'), isNull);
      expect(await db.settingValue('account.purity'), isNull);
    });

    test('forgetting them leaves every other setting alone', () async {
      await settings.saveStorageSettings(
        StorageSettings.defaults.copyWith(sfwTier: StorageTier.appPrivate),
      );
      await settings.saveAccountDefaults(_account);

      await settings.forgetAccountDefaults();

      final StorageSettings storage = await settings.loadStorageSettings();
      expect(storage.sfwTier, StorageTier.appPrivate);
    });

    test('a corrupt row costs the defaults, not the app', () async {
      // Browse simply opens on tela's own, which is where it opens before any
      // key is saved. A half-read account is not a state worth having.
      await settings.saveAccountDefaults(_account);
      await db.putSetting('account.categories', 'anime');

      expect(await settings.loadAccountDefaults(), isNull);
    });

    test('a half-written account reads as no account', () async {
      await db.putSetting('account.categories', '111');

      expect(await settings.loadAccountDefaults(), isNull);
    });
  });

  group('browse defaults source', () {
    test('answers the account before anything is chosen — an upgrade must not '
        "silently move somebody's front page", () async {
      expect(
        await settings.loadBrowseDefaultsSource(),
        BrowseDefaultsSource.account,
      );
    });

    test('round-trips the chosen source', () async {
      await settings.setBrowseDefaultsSource(BrowseDefaultsSource.device);

      expect(
        await settings.loadBrowseDefaultsSource(),
        BrowseDefaultsSource.device,
      );
      expect(await db.settingValue('browse.defaults.source'), 'device');
    });

    test('an unreadable source costs the choice, not the app', () async {
      await db.putSetting('browse.defaults.source', 'cloud');

      expect(
        await settings.loadBrowseDefaultsSource(),
        BrowseDefaultsSource.account,
      );
    });
  });

  group('device defaults', () {
    test('answers null before a snapshot is saved', () async {
      expect(await settings.loadDeviceDefaults(), isNull);
    });

    test('round-trips every field of a snapshot', () async {
      await settings.saveDeviceDefaults(_device);

      expect(await settings.loadDeviceDefaults(), _device);
    });

    test('stores the wire literals, readable in a sqlite3 shell', () async {
      await settings.saveDeviceDefaults(_device);

      expect(await db.settingValue('device.categories'), '001');
      expect(await db.settingValue('device.topRange'), '1y');
      expect(await db.settingValue('device.ratios'), '16x9');
      expect(await db.settingValue('device.order'), 'asc');
      expect(await db.settingValue('device.color'), '#0066cc');
    });

    test('never writes a device.purity row', () async {
      await settings.saveDeviceDefaults(_device);

      expect(await db.settingValue('device.purity'), isNull);
    });

    test('re-saving upserts rather than stacking', () async {
      await settings.saveDeviceDefaults(_device);
      await settings.saveDeviceDefaults(const BrowseDefaults());

      expect(await settings.loadDeviceDefaults(), const BrowseDefaults());
    });

    test('clearing the colour deletes the row rather than leaving the last '
        'swatch behind', () async {
      await settings.saveDeviceDefaults(_device);

      await settings.saveDeviceDefaults(const BrowseDefaults());

      // An upsert-only save would quietly re-apply a filter the user just
      // turned off: "any colour" is the absence of the row.
      expect(await db.settingValue('device.color'), isNull);
      expect((await settings.loadDeviceDefaults())?.color, isNull);
    });

    test('an empty ratio list round-trips as "any shape"', () async {
      const BrowseDefaults anyShape = BrowseDefaults(ratios: <String>[]);

      await settings.saveDeviceDefaults(anyShape);

      expect((await settings.loadDeviceDefaults())?.ratios, isEmpty);
    });

    test('a corrupt or half-written snapshot reads as none', () async {
      await settings.saveDeviceDefaults(_device);
      await db.putSetting('device.topRange', 'yesterday');

      expect(await settings.loadDeviceDefaults(), isNull);
    });

    test('saving a snapshot touches no other setting', () async {
      await settings.setPrivateLibraryLocked(locked: true);
      await settings.saveAccountDefaults(_account);

      await settings.saveDeviceDefaults(_device);

      expect(await settings.isPrivateLibraryLocked(), isTrue);
      expect(await settings.loadAccountDefaults(), _account);
    });
  });
}

/// A snapshot whose every field differs from tela's own defaults, so a round
/// trip cannot pass by accidentally reading a default back.
final BrowseDefaults _device = BrowseDefaults(
  categories: const CategoryFilter(<Category>{Category.people}),
  topRange: TopRange.oneYear,
  ratios: const <String>['16x9'],
  order: SortOrder.asc,
  color: WallpaperColor('#0066cc'),
);

/// An account that browses anime and tops by the week — both fields different
/// from tela's own defaults, so a round trip cannot pass by accidentally
/// reading a default back.
const AccountSettings _account = AccountSettings(
  categories: CategoryFilter(<Category>{Category.anime}),
  topRange: TopRange.oneWeek,
);
