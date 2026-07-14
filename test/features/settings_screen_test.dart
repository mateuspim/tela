import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/features/settings/settings_screen.dart';

import '../fakes/fake_settings_repository.dart';

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
  FakeSettingsRepository settings,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(settings),
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
