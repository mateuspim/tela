import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/features/settings/storage_tier_picker.dart';

import '../fakes/fake_image_store.dart';
import '../fakes/fake_settings_repository.dart';

void main() {
  const DownloadFolder onCard = DownloadFolder(
    volumeLabel: 'SD card',
    relativePath: 'Pictures/tela',
    isRemovable: true,
    isAvailable: true,
  );
  const String privateNote =
      'The private library always stays on this device. To keep explicit '
      'wallpapers on the SD card, choose Files, not gallery.';

  // Regression, owner 2026-10-16: explicit downloads were set to the card, yet
  // "Private library" kept saving to the device and Settings never said so.
  testWidgets('names the disk under each explicit destination', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      FakeImageStore(folder: onCard, sdCardAvailable: true),
      Purity.nsfw,
    );

    expect(find.text('Saves to SD card'), findsOneWidget);
    expect(find.text('Saves to Internal storage'), findsOneWidget);
    expect(find.text(privateNote), findsOneWidget);
  });

  testWidgets('says nothing about the card when there is none', (
    WidgetTester tester,
  ) async {
    await _pump(tester, FakeImageStore(), Purity.nsfw);

    expect(find.text('Saves to SD card'), findsNothing);
    expect(find.text(privateNote), findsNothing);
  });

  testWidgets('keeps the private-library note off the safe picker', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      FakeImageStore(folder: onCard, sdCardAvailable: true),
      Purity.sfw,
    );

    expect(find.text('Saves to SD card'), findsOneWidget);
    expect(find.text(privateNote), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester,
  FakeImageStore store,
  Purity purity,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        imageStoreProvider.overrideWithValue(store),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      ],
      child: MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StorageTierPicker(
              title: 'Destination',
              purity: purity,
              selected: StorageTier.filesOutsideGallery,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
