import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/features/settings/settings_screen.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_wallhaven_api.dart';

void main() {
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
}

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

Future<void> _pumpSettings(
  WidgetTester tester,
  FakeSettingsRepository settings, {
  FakeSecretStore? secrets,
  FakeWallhavenApi? api,
}) async {
  // Settings is a scrolling list, and it grew a download-history tile. On a
  // phone-sized test viewport the explicit picker falls below the fold and is
  // never built, which reads as "the setting vanished" rather than "scroll".
  tester.view
    ..physicalSize = const Size(1080, 3600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(settings),
        secretStoreProvider.overrideWithValue(secrets ?? FakeSecretStore()),
        wallhavenApiProvider.overrideWithValue(api ?? FakeWallhavenApi()),
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
