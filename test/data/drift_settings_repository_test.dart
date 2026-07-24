import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/data/settings/drift_settings_repository.dart';
import 'package:tela/domain/models/accent_color.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_destination_streak.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/resolution_filter.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tile_density.dart';
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

    test('has not acknowledged NSFW-on-removable until it is asked', () async {
      expect(await settings.loadNsfwOnRemovableAcknowledged(), isFalse);
    });

    test('round-trips the NSFW-on-removable acknowledgement', () async {
      await settings.saveNsfwOnRemovableAcknowledged(acknowledged: true);
      expect(await settings.loadNsfwOnRemovableAcknowledged(), isTrue);

      await settings.saveNsfwOnRemovableAcknowledged(acknowledged: false);
      expect(await settings.loadNsfwOnRemovableAcknowledged(), isFalse);
    });

    test('reads a corrupt acknowledgement as not acknowledged', () async {
      // The opposite of the lock: a warning fails *open* so it is shown. "I
      // can't tell whether this was accepted" means ask again, not stay quiet.
      await db.putSetting('privacy.nsfwOnRemovableAck', 'maybe');

      expect(await settings.loadNsfwOnRemovableAcknowledged(), isFalse);
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
      expect(await db.settingValue('device.resolution'), 'auto');
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
      const BrowseDefaults anyShape = BrowseDefaults(ratios: <RatioChoice>[]);

      await settings.saveDeviceDefaults(anyShape);

      expect((await settings.loadDeviceDefaults())?.ratios, isEmpty);
    });

    test('round-trips each resolution filter', () async {
      for (final ResolutionFilter filter in <ResolutionFilter>[
        const AutomaticResolution(),
        const AtLeastResolution(Resolution(1440, 2560)),
        ExactResolutions(const <Resolution>[
          Resolution(1920, 1080),
          Resolution(2560, 1440),
        ]),
      ]) {
        await settings.saveDeviceDefaults(
          BrowseDefaults(resolution: filter),
        );

        expect((await settings.loadDeviceDefaults())?.resolution, filter);
      }
    });

    test(
      'a snapshot saved before the resolution filter reads as Automatic',
      () async {
        await settings.saveDeviceDefaults(_device);
        // Exactly what an upgrading device's database looks like: every other
        // row present, and no device.resolution at all. No migration — the
        // settings table has taken every new setting this way since v1.
        await db.deleteSettings(<String>['device.resolution']);

        expect(
          (await settings.loadDeviceDefaults())?.resolution,
          const AutomaticResolution(),
        );
      },
    );

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

  group('accent colour', () {
    test('follows the device palette before anything is chosen', () async {
      expect(await settings.loadAccentColor(), isNull);
    });

    test('round-trips a chosen accent', () async {
      await settings.saveAccentColor(AccentColor(0x2c63e0));
      expect(await settings.loadAccentColor(), AccentColor(0x2c63e0));
    });

    test('stores a #rrggbb literal, readable in a sqlite3 shell', () async {
      await settings.saveAccentColor(AccentColor(0x2c63e0));
      expect(await db.settingValue('appearance.accent'), '#2c63e0');
    });

    test('re-choosing upserts rather than stacking rows', () async {
      await settings.saveAccentColor(AccentColor(0x2c63e0));
      await settings.saveAccentColor(AccentColor(0xcf5a18));
      expect(await settings.loadAccentColor(), AccentColor(0xcf5a18));
    });

    test('clearing deletes the row, so it follows the palette again', () async {
      await settings.saveAccentColor(AccentColor(0x2c63e0));
      await settings.clearAccentColor();
      expect(await settings.loadAccentColor(), isNull);
    });

    test('a corrupt row costs the accent, not the app', () async {
      await db.putSetting('appearance.accent', 'not-a-colour');
      expect(await settings.loadAccentColor(), isNull);
    });
  });

  group('tile density', () {
    test('draws at medium before anything is chosen', () async {
      // An upgrade must not silently resize somebody's wall.
      expect(await settings.loadTileDensity(), TileDensity.medium);
    });

    test('round-trips a chosen density', () async {
      await settings.saveTileDensity(TileDensity.large);
      expect(await settings.loadTileDensity(), TileDensity.large);
    });

    test('stores the constant name, readable in a sqlite3 shell', () async {
      await settings.saveTileDensity(TileDensity.small);
      expect(await db.settingValue('appearance.tileDensity'), 'small');
    });

    test('re-choosing upserts rather than stacking rows', () async {
      await settings.saveTileDensity(TileDensity.small);
      await settings.saveTileDensity(TileDensity.large);
      expect(await settings.loadTileDensity(), TileDensity.large);
    });

    test('a corrupt row costs the density, not the app', () async {
      await db.putSetting('appearance.tileDensity', 'enormous');
      expect(await settings.loadTileDensity(), TileDensity.medium);
    });
  });

  group('the destination streak', () {
    test('is absent until a download lands', () async {
      expect(await settings.loadDestinationStreak(Purity.sfw), isNull);
    });

    test('counts a run to the same tier', () async {
      await _record(settings, Purity.sfw, StorageTier.appPrivate, times: 3);

      final DownloadDestinationStreak? streak = await settings
          .loadDestinationStreak(Purity.sfw);
      expect(streak?.tier, StorageTier.appPrivate);
      expect(streak?.length, 3);
    });

    test('restarts when a download lands somewhere else', () async {
      await _record(settings, Purity.sfw, StorageTier.appPrivate, times: 3);
      await settings.recordDestination(Purity.sfw, StorageTier.sharedGallery);

      final DownloadDestinationStreak? streak = await settings
          .loadDestinationStreak(Purity.sfw);
      expect(streak?.tier, StorageTier.sharedGallery);
      expect(streak?.length, 1);
    });

    // Two knobs, not three: sketchy shares sfw's row exactly as it shares its
    // configured tier, so a sketchy download must lengthen the safe streak
    // rather than opening a third one.
    test('files sketchy in the safe bucket, not one of its own', () async {
      await settings.recordDestination(Purity.sfw, StorageTier.appPrivate);
      await settings.recordDestination(Purity.sketchy, StorageTier.appPrivate);

      expect((await settings.loadDestinationStreak(Purity.sketchy))?.length, 2);
      expect((await settings.loadDestinationStreak(Purity.sfw))?.length, 2);
    });

    test('keeps the explicit bucket separate from the safe one', () async {
      await _record(settings, Purity.sfw, StorageTier.sharedGallery, times: 2);
      await settings.recordDestination(Purity.nsfw, StorageTier.appPrivate);

      expect((await settings.loadDestinationStreak(Purity.sfw))?.length, 2);
      expect((await settings.loadDestinationStreak(Purity.nsfw))?.length, 1);
    });

    test('a corrupt row costs the suggestion, not the app', () async {
      await db.putSetting('downloads.streak.sfw', 'appPrivate:lots');
      expect(await settings.loadDestinationStreak(Purity.sfw), isNull);
    });

    // The same distrust `_tier` applies: a hand-edited row claiming an explicit
    // run landed in the gallery must not become a suggestion to route explicit
    // downloads there, which StorageSettings would then refuse to construct.
    test('refuses a stored streak the purity could never have', () async {
      await db.putSetting('downloads.streak.nsfw', 'sharedGallery:5');
      expect(await settings.loadDestinationStreak(Purity.nsfw), isNull);
    });
  });

  group('the "Keep sending here" pin', () {
    test('is absent until one is set', () async {
      expect(await settings.loadPinnedDownloadTier(), isNull);
    });

    test('round-trips every tier, including the gallery', () async {
      for (final StorageTier tier in StorageTier.values) {
        await settings.setPinnedDownloadTier(tier);
        expect(await settings.loadPinnedDownloadTier(), tier);
      }
    });

    test('clears back to no pin', () async {
      await settings.setPinnedDownloadTier(StorageTier.appPrivate);
      await settings.setPinnedDownloadTier(null);
      expect(await settings.loadPinnedDownloadTier(), isNull);
    });

    test('reads an unrecognised row as no pin', () async {
      await db.putSetting('downloads.pinned', 'dropbox');
      expect(await settings.loadPinnedDownloadTier(), isNull);
    });
  });
}

/// Records [times] downloads of [purity] all landing in [tier].
Future<void> _record(
  DriftSettingsRepository settings,
  Purity purity,
  StorageTier tier, {
  required int times,
}) async {
  for (int i = 0; i < times; i++) {
    await settings.recordDestination(purity, tier);
  }
}

/// A snapshot whose every field differs from tela's own defaults, so a round
/// trip cannot pass by accidentally reading a default back.
final BrowseDefaults _device = BrowseDefaults(
  categories: const CategoryFilter(<Category>{Category.people}),
  topRange: TopRange.oneYear,
  ratios: const <RatioChoice>[ExactRatio(16, 9)],
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
