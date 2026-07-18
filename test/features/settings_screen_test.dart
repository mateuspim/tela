import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/accent_color.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tile_density.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/ports/app_lock.dart';
import 'package:tela/features/settings/settings_screen.dart';

import '../fakes/fake_app_lock.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_wallhaven_api.dart';

void main() {
  testWidgets('groups related settings into six scannable sections', (
    WidgetTester tester,
  ) async {
    await _pumpSettings(tester, FakeSettingsRepository());

    expect(find.byType(Card), findsNWidgets(6));
    expect(find.text('Wallhaven account'), findsWidgets);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Browse defaults'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    // Its own section, not a line under Downloads: a download is a file the
    // user kept, and the cache is a copy tela can fetch again.
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
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
      api: FakeWallhavenApi(failure: const InvalidApiKeyFailure()),
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
    final FakeWallhavenApi api = FakeWallhavenApi(account: _refreshed);
    await _pumpSettings(
      tester,
      settings,
      secrets: FakeSecretStore(storedKey: 'abc123'),
      api: api,
    );

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(api.accountSettingsCalls, 1);
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
      api: FakeWallhavenApi(failure: const NetworkFailure()),
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

      await tester.tap(find.byType(SwitchListTile));
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

      await tester.tap(find.byType(SwitchListTile));
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

      await tester.tap(find.byType(SwitchListTile));
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

      await tester.tap(find.byType(SwitchListTile));
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

      await tester.tap(find.byType(SwitchListTile));
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

      expect(find.byType(SwitchListTile), findsNothing);
      expect(
        find.textContaining('Needs a screen lock or fingerprint'),
        findsOneWidget,
      );
      expect(settings.lockSaved, isFalse);
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

Future<void> _pumpSettings(
  WidgetTester tester,
  FakeSettingsRepository settings, {
  FakeSecretStore? secrets,
  FakeWallhavenApi? api,
  FakeAppLock? lock,
}) async {
  // Settings is a scrolling list, and it keeps growing — a download-history
  // tile, and now the browse-defaults switch. On a phone-sized test viewport
  // the pickers below the fold are never built, which reads as "the setting
  // vanished" rather than "scroll down". Every new section pushes this taller.
  tester.view
    ..physicalSize = const Size(1080, 5000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(settings),
        secretStoreProvider.overrideWithValue(secrets ?? FakeSecretStore()),
        wallhavenApiProvider.overrideWithValue(api ?? FakeWallhavenApi()),
        appLockProvider.overrideWithValue(lock ?? FakeAppLock()),
      ],
      child: const MaterialApp(
        localizationsDelegates: <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
