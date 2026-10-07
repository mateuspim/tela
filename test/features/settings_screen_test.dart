import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/build_edition.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/band_fade_edge.dart';
import 'package:tela/domain/models/accent_color.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tile_density.dart';
import 'package:tela/domain/ports/app_lock.dart';
import 'package:tela/features/settings/settings_screen.dart';

import '../fakes/fake_app_lock.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_wallpaper_source.dart';

void main() {
  testWidgets('the page starts clear of the band fade at rest', (
    WidgetTester tester,
  ) async {
    await _pumpSettings(tester, FakeSettingsRepository());

    // The band dissolves what scrolls up under it (owner, 2026-10-06); a page
    // at rest must not start inside that fade.
    expect(find.byType(BandFadeEdge), findsOneWidget);
    final double fadeBottom =
        tester.getTopLeft(find.byType(BandFadeEdge)).dy + BandFadeEdge.height;
    expect(
      tester.getTopLeft(find.byType(Card).first).dy,
      greaterThanOrEqualTo(fadeBottom),
    );
  });

  testWidgets('groups related settings into scannable sections', (
    WidgetTester tester,
  ) async {
    await _pumpSettings(tester, FakeSettingsRepository());

    expect(find.byType(Card), findsNWidgets(7));
    expect(find.text('Wallhaven account'), findsWidgets);
    expect(find.text('Appearance'), findsOneWidget);
    // Its own group, not a row under Appearance: that one is about how tela
    // looks, this one is about what tela puts on the device's screen.
    expect(find.text('Wallpaper'), findsOneWidget);
    expect(find.text('Browse defaults'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    // Its own section, not a line under Downloads: a download is a file the
    // user kept, and the cache is a copy tela can fetch again.
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
  });

  testWidgets('ends its two columns together on a landscape tablet', (
    WidgetTester tester,
  ) async {
    // The SM-X730's landscape geometry, where the static split was seen: the
    // left column ended less than halfway down and the rest was dead space.
    await _pumpSettings(
      tester,
      FakeSettingsRepository(),
      viewport: const Size(2560, 1600),
      pixelRatio: 2.125,
    );

    final List<Rect> cards = tester
        .widgetList<Card>(find.byType(Card))
        .map((Card card) => tester.getRect(find.byWidget(card)))
        .toList();
    final Set<double> lefts = cards.map((Rect card) => card.left).toSet();
    expect(lefts, hasLength(2), reason: 'expected two columns');

    final List<double> bottoms = lefts
        .map(
          (double left) => cards
              .where((Rect card) => card.left == left)
              .map((Rect card) => card.bottom)
              .reduce(math.max),
        )
        .toList();
    // Measured against the tallest group rather than a constant, because that
    // is the actual bound: dropping each block into the shortest column can
    // never leave the columns further apart than the last block placed, so
    // "under one group's worth of drift" *is* as balanced as discrete blocks
    // can be. Hardcoding the number instead made this test re-fail every time
    // a group grew a row — it did, when the collections rows landed in the
    // account group — while proving nothing more. The static split was ~2x.
    final double tallest = cards
        .map((Rect card) => card.height)
        .reduce(math.max);
    expect((bottoms.first - bottoms.last).abs(), lessThan(tallest));
  });

  testWidgets('pads its last group clear of the bottom system bar', (
    WidgetTester tester,
  ) async {
    // Under edge-to-edge the body draws behind the gesture/nav bar; without
    // this the final group (the download folder) strands behind it with no
    // scroll extent left to lift it. Device-seen 2026-07-21 behind Samsung's
    // taskbar.
    await _pumpSettings(
      tester,
      FakeSettingsRepository(),
      viewport: const Size(2560, 1600),
      pixelRatio: 2.125,
      bottomInset: 48,
    );

    final SingleChildScrollView scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect((scroll.padding! as EdgeInsets).bottom, 32 + 48);
  });

  testWidgets('shows the saved destination for each purity', (
    WidgetTester tester,
  ) async {
    await _pumpSettings(
      tester,
      FakeSettingsRepository(
        settings: StorageSettings(
          sfwTier: StorageTier.appPrivate,
          nsfwTier: StorageTier.filesOutsideGallery,
        ),
      ),
    );

    expect(find.text('Safe and sketchy wallpapers'), findsOneWidget);
    expect(find.text('Explicit wallpapers'), findsOneWidget);
    expect(_selectedTiers(tester), <StorageTier>[
      StorageTier.appPrivate,
      StorageTier.filesOutsideGallery,
    ]);
  });

  testWidgets('persists a changed destination immediately', (
    WidgetTester tester,
  ) async {
    final FakeSettingsRepository settings = FakeSettingsRepository();
    await _pumpSettings(tester, settings);

    await tester.tap(find.text('Files, not gallery').first);
    await tester.pumpAndSettle();

    expect(settings.saved.sfwTier, StorageTier.filesOutsideGallery);
    expect(settings.saved.nsfwTier, StorageTier.appPrivate);
  });

  testWidgets('reveals the device/card choice only when files-tier is used', (
    WidgetTester tester,
  ) async {
    // Dead control otherwise: the volume choice means nothing until a purity
    // actually routes to files-outside-gallery, so it stays hidden until then.
    await _pumpSettings(tester, FakeSettingsRepository());
    expect(find.text('Where files are saved'), findsNothing);

    await tester.tap(find.text('Files, not gallery').first);
    await tester.pumpAndSettle();

    expect(find.text('Where files are saved'), findsOneWidget);
    expect(find.text('SD card'), findsNothing); // no card in this fake
  });

  // Regression for device pass F7 (2026-10-03): a folder chosen from the
  // download chooser for a one-off "Files" download was invisible in Settings
  // until a default was switched to Files.
  testWidgets('shows a folder already chosen even when no default uses it', (
    WidgetTester tester,
  ) async {
    await _pumpSettings(
      tester,
      FakeSettingsRepository(),
      imageStore: FakeImageStore(
        folder: const DownloadFolder(
          volumeLabel: 'SD card',
          relativePath: 'Wallpapers/tela',
          isRemovable: true,
          isAvailable: true,
        ),
      ),
    );

    expect(find.text('Where files are saved'), findsOneWidget);
    expect(find.textContaining('SD card/Wallpapers/tela'), findsOneWidget);
  });

  testWidgets(
    'offers the SD card once files-tier routes there and a card is in',
    (
      WidgetTester tester,
    ) async {
      await _pumpSettings(
        tester,
        FakeSettingsRepository(
          settings: StorageSettings(
            sfwTier: StorageTier.filesOutsideGallery,
            nsfwTier: StorageTier.appPrivate,
          ),
        ),
        imageStore: FakeImageStore(sdCardAvailable: true),
      );

      expect(find.text('Where files are saved'), findsOneWidget);
      expect(find.text('SD card'), findsOneWidget);
    },
  );

  testWidgets('opens on the density the wall is already drawing at', (
    WidgetTester tester,
  ) async {
    await _pumpSettings(
      tester,
      FakeSettingsRepository(density: TileDensity.small),
    );

    expect(_selectedDensity(tester), TileDensity.small);
  });

  testWidgets('persists a chosen tile density immediately', (
    WidgetTester tester,
  ) async {
    // There is no save button on this screen: a density that lit up but did
    // not save would be a wall size the user believes is set.
    final FakeSettingsRepository settings = FakeSettingsRepository();
    await _pumpSettings(tester, settings);

    await tester.tap(find.text('Large'));
    await tester.pumpAndSettle();

    expect(await settings.loadTileDensity(), TileDensity.large);
    expect(_selectedDensity(tester), TileDensity.large);
  });

  testWidgets('offers a way to the blocked-tags screen', (
    WidgetTester tester,
  ) async {
    await _pumpSettings(tester, FakeSettingsRepository());

    expect(find.text('Blocked tags'), findsOneWidget);
    expect(
      find.text('Tags hidden from every search, wherever you blocked them.'),
      findsOneWidget,
    );
  });

  testWidgets('never offers the gallery for explicit wallpapers', (
    WidgetTester tester,
  ) async {
    await _pumpSettings(tester, FakeSettingsRepository());

    // The gallery is offered exactly once: to the safe/sketchy picker.
    expect(find.text('Gallery'), findsOneWidget);
    expect(
      find.text('Explicit wallpapers are never added to the gallery.'),
      findsOneWidget,
    );
  });

  testWidgets('says whether an API key is stored, and never what it is', (
    WidgetTester tester,
  ) async {
    final FakeSecretStore secrets = FakeSecretStore(storedKey: 'topsecret');
    await _pumpSettings(tester, FakeSettingsRepository(), secrets: secrets);

    expect(
      find.text('Saved. Explicit wallpapers are unlocked.'),
      findsOneWidget,
    );
    expect(find.textContaining('topsecret'), findsNothing);
  });

  testWidgets('saves a trimmed key that Wallhaven accepts', (
    WidgetTester tester,
  ) async {
    final FakeSecretStore secrets = FakeSecretStore();
    await _pumpSettings(tester, FakeSettingsRepository(), secrets: secrets);

    await _enterKey(tester, '  abc123  ');

    expect(secrets.storedKey, 'abc123');
    expect(find.text('API key saved.'), findsOneWidget);
    expect(
      find.text('Saved. Explicit wallpapers are unlocked.'),
      findsOneWidget,
    );
  });

  testWidgets('stores nothing and says so when the key is rejected', (
    WidgetTester tester,
  ) async {
    final FakeSecretStore secrets = FakeSecretStore();
    await _pumpSettings(
      tester,
      FakeSettingsRepository(),
      secrets: secrets,
      source: FakeWallpaperSource(failure: const InvalidApiKeyFailure()),
    );

    await _enterKey(tester, 'nope');

    expect(secrets.storedKey, isNull);
    expect(find.text('That Wallhaven API key was rejected.'), findsOneWidget);
    expect(
      find.text('Not set. Required for explicit wallpapers.'),
      findsOneWidget,
    );
  });

  testWidgets('removes the stored key', (WidgetTester tester) async {
    final FakeSecretStore secrets = FakeSecretStore(storedKey: 'abc123');
    await _pumpSettings(tester, FakeSettingsRepository(), secrets: secrets);

    await tester.tap(find.byTooltip('Remove API key'));
    await tester.pumpAndSettle();

    expect(secrets.storedKey, isNull);
    expect(find.text('API key removed.'), findsOneWidget);
    expect(
      find.text('Not set. Required for explicit wallpapers.'),
      findsOneWidget,
    );
  });

  testWidgets('offers both browse-default sources, on the account by default', (
    WidgetTester tester,
  ) async {
    await _pumpSettings(
      tester,
      FakeSettingsRepository(accountDefaults: _account),
      secrets: FakeSecretStore(storedKey: 'abc123'),
    );

    expect(find.text('Wallhaven account'), findsWidgets);
    expect(find.text('This device'), findsOneWidget);
    expect(_selectedSource(tester), BrowseDefaultsSource.account);
    // The account's own filters, summarised — not tela's.
    expect(find.textContaining('Anime'), findsOneWidget);
    expect(find.textContaining('Last week'), findsOneWidget);
  });

  testWidgets('withholds the account source until a key is stored — there is '
      'no account to read without one', (WidgetTester tester) async {
    await _pumpSettings(tester, FakeSettingsRepository());

    expect(
      find.text("Add an API key to use your account's settings."),
      findsOneWidget,
    );
    final RadioListTile<BrowseDefaultsSource> account = tester
        .widget<RadioListTile<BrowseDefaultsSource>>(
          find.byWidgetPredicate(
            (Widget widget) =>
                widget is RadioListTile<BrowseDefaultsSource> &&
                widget.value == BrowseDefaultsSource.account,
          ),
        );
    expect(account.enabled, isFalse);
  });

  // Regression for device pass F6 (2026-10-03): Safe showed a key promise and
  // a disabled account row pointing at a key field it does not have.
  testWidgets('an edition without credentials promises no key or explicit '
      'content', (WidgetTester tester) async {
    await _pumpSettings(
      tester,
      FakeSettingsRepository(),
      edition: BuildEdition.safe,
    );

    expect(find.textContaining('Connect your key'), findsNothing);
    expect(
      find.text('Your username opens your public collections.'),
      findsOneWidget,
    );
  });

  testWidgets('an edition without credentials offers only the device source', (
    WidgetTester tester,
  ) async {
    await _pumpSettings(
      tester,
      FakeSettingsRepository(),
      edition: BuildEdition.play,
    );

    expect(
      find.text("Add an API key to use your account's settings."),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is RadioListTile<BrowseDefaultsSource> &&
            widget.value == BrowseDefaultsSource.account,
      ),
      findsNothing,
    );
    expect(find.text('This device'), findsOneWidget);
  });

  testWidgets('each row summarises its own source, never the one in force', (
    WidgetTester tester,
  ) async {
    // Regression: the account row rendered whichever defaults were *active*, so
    // selecting the device made the account's line read back the device's
    // filters — and that line is what you consult before switching. Found on
    // hardware (2026-07-14), where a device snapshot of "Last 24 hours" showed
    // up on an account whose toplist range is Last month.
    await _pumpSettings(
      tester,
      FakeSettingsRepository(
        accountDefaults: _account,
        source: BrowseDefaultsSource.device,
        deviceDefaults: _device,
      ),
      secrets: FakeSecretStore(storedKey: 'abc123'),
    );

    expect(_selectedSource(tester), BrowseDefaultsSource.device);
    // The account's own: anime, by the week.
    expect(find.textContaining('Anime · Last week'), findsOneWidget);
    // The device's own: people, by the year — and never on the account's row.
    expect(find.textContaining('People · Last year'), findsOneWidget);
  });

  testWidgets('the device row says how to save one before one exists', (
    WidgetTester tester,
  ) async {
    await _pumpSettings(
      tester,
      FakeSettingsRepository(accountDefaults: _account),
      secrets: FakeSecretStore(storedKey: 'abc123'),
    );

    expect(find.text('Set filters, then tap Save as default.'), findsOneWidget);
  });

  testWidgets('picking a source persists it', (WidgetTester tester) async {
    final FakeSettingsRepository settings = FakeSettingsRepository(
      accountDefaults: _account,
    );
    await _pumpSettings(
      tester,
      settings,
      secrets: FakeSecretStore(storedKey: 'abc123'),
    );

    await tester.tap(find.text('This device'));
    await tester.pumpAndSettle();

    expect(settings.sourceSaved, BrowseDefaultsSource.device);
    expect(_selectedSource(tester), BrowseDefaultsSource.device);
  });

  testWidgets('refreshing re-pulls the account and says so', (
    WidgetTester tester,
  ) async {
    final FakeSettingsRepository settings = FakeSettingsRepository(
      accountDefaults: _account,
    );
    final FakeWallpaperSource source = FakeWallpaperSource(account: _refreshed);
    await _pumpSettings(
      tester,
      settings,
      secrets: FakeSecretStore(storedKey: 'abc123'),
      source: source,
    );

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(source.accountSettingsCalls, 1);
    expect(settings.accountSaved, _refreshed);
    expect(
      find.text('Browse defaults updated from your account.'),
      findsOneWidget,
    );
  });

  testWidgets('a refresh tela cannot make keeps the defaults it already had', (
    WidgetTester tester,
  ) async {
    final FakeSettingsRepository settings = FakeSettingsRepository(
      accountDefaults: _account,
    );
    await _pumpSettings(
      tester,
      settings,
      secrets: FakeSecretStore(storedKey: 'abc123'),
      source: FakeWallpaperSource(failure: const NetworkFailure()),
    );

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    // Being offline says nothing about an account, exactly as it says nothing
    // about a key.
    expect(settings.accountSaved, _account);
    expect(find.textContaining('Anime'), findsOneWidget);
  });

  group('accent color', () {
    testWidgets('follows the wallpaper until a colour is picked', (
      WidgetTester tester,
    ) async {
      final FakeSettingsRepository settings = FakeSettingsRepository();
      await _pumpSettings(tester, settings);

      expect(find.text('Accent color'), findsOneWidget);
      expect(find.bySemanticsLabel('Follow wallpaper'), findsOneWidget);
      expect(settings.accentSaved, isNull);
    });

    testWidgets('picking a preset persists it immediately', (
      WidgetTester tester,
    ) async {
      // No save button, like every other setting here: a screen that can be
      // closed mid-edit must not be able to lose the edit.
      final FakeSettingsRepository settings = FakeSettingsRepository();
      await _pumpSettings(tester, settings);

      await tester.tap(find.bySemanticsLabel('Accent #2c63e0'));
      await tester.pumpAndSettle();

      expect(settings.accentSaved, AccentColor(0x2c63e0));
    });

    testWidgets('going back to follow wallpaper clears the accent', (
      WidgetTester tester,
    ) async {
      final FakeSettingsRepository settings = FakeSettingsRepository(
        accent: AccentColor(0x2c63e0),
      );
      await _pumpSettings(tester, settings);

      await tester.tap(find.bySemanticsLabel('Follow wallpaper'));
      await tester.pumpAndSettle();

      expect(settings.accentSaved, isNull);
    });
  });

  group('explicit-on-removable warning', () {
    // The first edge: the folder is already on a removable card, and moving the
    // NSFW picker onto files-outside-gallery is what routes explicit downloads
    // there. (The other edge — choosing the card while NSFW already routes to
    // files — is covered in download_location_section_test.)
    const DownloadFolder onCard = DownloadFolder(
      volumeLabel: 'SD card',
      relativePath: 'tela',
      isRemovable: true,
      isAvailable: true,
    );

    testWidgets('warns when explicit files land on an already-removable card', (
      WidgetTester tester,
    ) async {
      final FakeSettingsRepository settings = FakeSettingsRepository();
      await _pumpSettings(
        tester,
        settings,
        imageStore: FakeImageStore(folder: onCard, sdCardAvailable: true),
      );

      // The NSFW picker's files option is the second on screen.
      await tester.tap(find.text('Files, not gallery').last);
      await tester.pumpAndSettle();

      expect(
        find.text('Explicit downloads on a removable card'),
        findsOneWidget,
      );
    });

    testWidgets('using the card anyway keeps NSFW on files and acknowledges', (
      WidgetTester tester,
    ) async {
      final FakeSettingsRepository settings = FakeSettingsRepository();
      await _pumpSettings(
        tester,
        settings,
        imageStore: FakeImageStore(folder: onCard, sdCardAvailable: true),
      );

      await tester.tap(find.text('Files, not gallery').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use card anyway'));
      await tester.pumpAndSettle();

      expect(settings.saved.nsfwTier, StorageTier.filesOutsideGallery);
      expect(settings.nsfwOnRemovableAckSaved, isTrue);
    });

    testWidgets('declining leaves explicit downloads in the private library', (
      WidgetTester tester,
    ) async {
      final FakeSettingsRepository settings = FakeSettingsRepository();
      await _pumpSettings(
        tester,
        settings,
        imageStore: FakeImageStore(folder: onCard, sdCardAvailable: true),
      );

      await tester.tap(find.text('Files, not gallery').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use private library'));
      await tester.pumpAndSettle();

      expect(settings.saved.nsfwTier, StorageTier.appPrivate);
      expect(settings.nsfwOnRemovableAckSaved, isFalse);
    });

    testWidgets('no warning when the explicit folder is on the device', (
      WidgetTester tester,
    ) async {
      await _pumpSettings(
        tester,
        FakeSettingsRepository(),
        imageStore: FakeImageStore(
          folder: const DownloadFolder(
            volumeLabel: 'Internal storage',
            relativePath: 'tela',
            isRemovable: false,
            isAvailable: true,
          ),
        ),
      );

      await tester.tap(find.text('Files, not gallery').last);
      await tester.pumpAndSettle();

      expect(
        find.text('Explicit downloads on a removable card'),
        findsNothing,
      );
    });
  });

  group('the download pin', () {
    testWidgets('says a pin is in force, and offers to stop it', (
      WidgetTester tester,
    ) async {
      // The gap this closes: a pin silences the destination chooser on every
      // screen that downloads, so it is the one setting the user stops being
      // shown at the moment it starts working. It read as "downloading does
      // not ask me where any more", with nowhere to find out why.
      final FakeSettingsRepository settings = FakeSettingsRepository(
        pinnedDownloadTier: StorageTier.appPrivate,
      );
      await _pumpSettings(tester, settings);

      expect(
        find.text('Sending every download to Private library.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('settings-stop-download-pin')));
      await tester.pumpAndSettle();

      expect(settings.pinnedTierSaved, isNull);
      expect(find.byKey(const Key('settings-stop-download-pin')), findsNothing);
    });

    testWidgets('stays out of the way when no pin is set', (
      WidgetTester tester,
    ) async {
      // Most users never turn this on, and a permanent row explaining a
      // feature that is off is worse than no row at all.
      await _pumpSettings(tester, FakeSettingsRepository());

      expect(find.byKey(const Key('settings-stop-download-pin')), findsNothing);
      expect(find.textContaining('Sending every download'), findsNothing);
    });
  });

  group('app-lock switch', () {
    testWidgets('turning the lock off asks for proof first', (
      WidgetTester tester,
    ) async {
      // The gate on the library is worth nothing if the switch that removes it
      // is one ungated tap away on an open screen.
      final FakeSettingsRepository settings = FakeSettingsRepository(
        privateLibraryLocked: true,
      );
      final FakeAppLock lock = FakeAppLock();
      await _pumpSettings(tester, settings, lock: lock);

      await tester.tap(_appLockSwitch);
      await tester.pumpAndSettle();

      expect(lock.prompts, 1);
      expect(settings.lockSaved, isFalse);
    });

    testWidgets('a refused prompt leaves the lock on', (
      WidgetTester tester,
    ) async {
      final FakeSettingsRepository settings = FakeSettingsRepository(
        privateLibraryLocked: true,
      );
      await _pumpSettings(
        tester,
        settings,
        lock: FakeAppLock(passes: false),
      );

      await tester.tap(_appLockSwitch);
      await tester.pumpAndSettle();

      expect(settings.lockSaved, isTrue);
    });

    testWidgets('a locked-out sensor cannot switch the lock off', (
      WidgetTester tester,
    ) async {
      // The load-bearing one. A lockout is the lock *working* — five bad reads
      // is what a stranger's finger looks like. If it opened this switch, then
      // failing the fingerprint five times would itself be the way past the
      // lock, which is the hardware bug of 2026-07-14 moved rather than fixed.
      final FakeSettingsRepository settings = FakeSettingsRepository(
        privateLibraryLocked: true,
      );
      await _pumpSettings(
        tester,
        settings,
        lock: FakeAppLock(
          available: false,
          outcome: AppLockOutcome.lockedOut,
        ),
      );

      await tester.tap(_appLockSwitch);
      await tester.pumpAndSettle();

      expect(settings.lockSaved, isTrue);
      expect(find.textContaining('Too many attempts'), findsOneWidget);
    });

    testWidgets('a device that cannot ask may still switch the lock off', (
      WidgetTester tester,
    ) async {
      // The escape hatch, and the only outcome besides a pass that opens this
      // switch: app-private files live nowhere else, so a device that can never
      // answer a prompt must not strand its owner outside them for good.
      final FakeSettingsRepository settings = FakeSettingsRepository(
        privateLibraryLocked: true,
      );
      await _pumpSettings(
        tester,
        settings,
        lock: FakeAppLock(
          available: false,
          outcome: AppLockOutcome.unavailable,
        ),
      );

      await tester.tap(_appLockSwitch);
      await tester.pumpAndSettle();

      expect(settings.lockSaved, isFalse);
    });

    testWidgets('turning the lock on asks for nothing', (
      WidgetTester tester,
    ) async {
      // There is nothing to prove yet, and demanding a fingerprint to *add*
      // protection only teaches people not to bother.
      final FakeSettingsRepository settings = FakeSettingsRepository();
      final FakeAppLock lock = FakeAppLock();
      await _pumpSettings(tester, settings, lock: lock);

      await tester.tap(_appLockSwitch);
      await tester.pumpAndSettle();

      expect(lock.prompts, 0);
      expect(settings.lockSaved, isTrue);
    });

    testWidgets('is not offered at all when nothing could satisfy it', (
      WidgetTester tester,
    ) async {
      final FakeSettingsRepository settings = FakeSettingsRepository();
      await _pumpSettings(
        tester,
        settings,
        lock: FakeAppLock(available: false),
      );

      expect(_appLockSwitch, findsNothing);
      expect(
        find.textContaining('Needs a screen lock or fingerprint'),
        findsOneWidget,
      );
      expect(settings.lockSaved, isFalse);
    });
  });

  group('the explicit beam gate', () {
    testWidgets('is off on a fresh install', (WidgetTester tester) async {
      // The single safeguard behind tela's one deliberate exception to
      // "explicit pixels never leave the app". A default of on would make that
      // exception the rule.
      await _pumpSettings(tester, FakeSettingsRepository());

      expect(
        tester.widget<SwitchListTile>(_beamSwitch).value,
        isFalse,
      );
    });

    testWidgets('persists being turned on immediately', (
      WidgetTester tester,
    ) async {
      final FakeSettingsRepository settings = FakeSettingsRepository();
      await _pumpSettings(tester, settings);

      await tester.tap(_beamSwitch);
      await tester.pumpAndSettle();

      // Written before the switch moves: a gate that lit up but did not save is
      // one the user believes is on until the next cold start says otherwise.
      expect(settings.explicitBeamAllowed, isTrue);
    });

    testWidgets('opens on the stored value', (WidgetTester tester) async {
      await _pumpSettings(
        tester,
        FakeSettingsRepository()..explicitBeamAllowed = true,
      );

      expect(tester.widget<SwitchListTile>(_beamSwitch).value, isTrue);
    });

    testWidgets('turns back off', (WidgetTester tester) async {
      final FakeSettingsRepository settings = FakeSettingsRepository()
        ..explicitBeamAllowed = true;
      await _pumpSettings(tester, settings);

      await tester.tap(_beamSwitch);
      await tester.pumpAndSettle();

      expect(settings.explicitBeamAllowed, isFalse);
    });
  });
}

/// The source the browse-defaults radio currently has selected.
BrowseDefaultsSource? _selectedSource(WidgetTester tester) {
  return tester
      .widget<RadioGroup<BrowseDefaultsSource>>(
        find.byType(RadioGroup<BrowseDefaultsSource>),
      )
      .groupValue;
}

/// An account browsing anime by the week — every field differs from tela's own
/// defaults, so a summary cannot pass by reading a default back.
const AccountSettings _account = AccountSettings(
  categories: CategoryFilter(<Category>{Category.anime}),
  topRange: TopRange.oneWeek,
);

/// What the account says after somebody changed it on the web.
const AccountSettings _refreshed = AccountSettings(
  categories: CategoryFilter(<Category>{Category.general}),
  topRange: TopRange.oneYear,
);

/// A snapshot sharing no field with [_account], so one row cannot pass for the
/// other.
const BrowseDefaults _device = BrowseDefaults(
  categories: CategoryFilter(<Category>{Category.people}),
  topRange: TopRange.oneYear,
);

/// Opens the key dialog, types [key], and saves.
Future<void> _enterKey(WidgetTester tester, String key) async {
  await tester.tap(find.text('API key'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), key);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
}

/// The checked tier of each picker, in screen order: safe/sketchy, then nsfw.
List<StorageTier?> _selectedTiers(WidgetTester tester) {
  return tester
      .widgetList<RadioGroup<StorageTier>>(find.byType(RadioGroup<StorageTier>))
      .map((RadioGroup<StorageTier> group) => group.groupValue)
      .toList();
}

/// The tile size the density picker currently shows as on.
TileDensity _selectedDensity(WidgetTester tester) {
  return tester
      .widget<SegmentedButton<TileDensity>>(
        find.byType(SegmentedButton<TileDensity>),
      )
      .selected
      .single;
}

/// The explicit-beam toggle specifically. See [_appLockSwitch].
final Finder _beamSwitch = find.ancestor(
  of: find.text('Beam explicit wallpapers'),
  matching: find.byType(SwitchListTile),
);

/// The app-lock toggle specifically.
///
/// Was `find.byType(SwitchListTile)`, which stopped meaning one thing the
/// moment Privacy grew a second switch (the explicit beam). Finding it by its
/// own title says which switch the test is about, and cannot go ambiguous
/// again.
final Finder _appLockSwitch = find.ancestor(
  of: find.text('Lock the private library'),
  matching: find.byType(SwitchListTile),
);

Future<void> _pumpSettings(
  WidgetTester tester,
  FakeSettingsRepository settings, {
  FakeSecretStore? secrets,
  FakeWallpaperSource? source,
  FakeAppLock? lock,
  FakeImageStore? imageStore,
  BuildEdition edition = BuildEdition.full,
  Size viewport = const Size(1080, 5000),
  double pixelRatio = 1,
  double bottomInset = 0,
}) async {
  // Settings is a scrolling list, and it keeps growing — a download-history
  // tile, and now the browse-defaults switch. On a phone-sized test viewport
  // the pickers below the fold are never built, which reads as "the setting
  // vanished" rather than "scroll down". Every new section pushes this taller.
  // A caller judging the *layout* rather than a control passes real geometry.
  tester.view
    ..physicalSize = viewport
    ..devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(settings),
        secretStoreProvider.overrideWithValue(secrets ?? FakeSecretStore()),
        wallhavenSourceProvider.overrideWithValue(
          source ?? FakeWallpaperSource(),
        ),
        appLockProvider.overrideWithValue(lock ?? FakeAppLock()),
        imageStoreProvider.overrideWithValue(imageStore ?? FakeImageStore()),
        buildEditionProvider.overrideWithValue(edition),
      ],
      child: MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        // Injects a bottom system-bar inset above the Scaffold, the way an
        // edge-to-edge gesture bar or nav bar would, so a test can prove the
        // scroll content pads itself clear of it.
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: EdgeInsets.only(bottom: bottomInset),
          ),
          child: child!,
        ),
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
