import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';
import 'package:tela/features/settings/download_location_section.dart';

import '../fakes/fake_image_store.dart';
import '../fakes/fake_settings_repository.dart';

void main() {
  const DownloadFolder onCard = DownloadFolder(
    volumeLabel: 'SD card',
    relativePath: 'Wallpapers/tela',
    isRemovable: true,
    isAvailable: true,
    freeBytes: 8589934592,
  );
  const DownloadFolder onDevice = DownloadFolder(
    volumeLabel: 'Internal storage',
    relativePath: 'tela',
    isRemovable: false,
    isAvailable: true,
  );

  testWidgets('offers device always and card only when one is available', (
    WidgetTester tester,
  ) async {
    await _pump(tester, FakeImageStore());

    expect(find.text('Internal storage'), findsOneWidget);
    expect(find.text('SD card'), findsNothing);
  });

  testWidgets('shows the card option when a card is in the slot', (
    WidgetTester tester,
  ) async {
    await _pump(tester, FakeImageStore(sdCardAvailable: true));

    expect(find.text('Internal storage'), findsOneWidget);
    expect(find.text('SD card'), findsOneWidget);
  });

  testWidgets('marks the current volume and shows where files land', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      FakeImageStore(folder: onCard, sdCardAvailable: true),
    );

    expect(_selectedKind(tester), StorageVolumeKind.sdCard);
    expect(find.textContaining('SD card/Wallpapers/tela'), findsOneWidget);
    expect(find.textContaining('8.0 GB free'), findsOneWidget);
  });

  testWidgets('an ejected card still shows, marked unavailable, not unset', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      // Card gone from the slot (sdCardAvailable false); folder is still on it.
      FakeImageStore(
        folder: const DownloadFolder(
          volumeLabel: 'SD card',
          relativePath: 'tela',
          isRemovable: true,
          isAvailable: false,
        ),
      ),
    );

    // The user's own choice must not vanish just because the card is out.
    expect(find.text('SD card'), findsOneWidget);
    expect(_selectedKind(tester), StorageVolumeKind.sdCard);
    expect(find.textContaining('Unavailable'), findsOneWidget);
  });

  testWidgets('picking a volume opens the picker aimed at it', (
    WidgetTester tester,
  ) async {
    final FakeImageStore store = FakeImageStore(
      sdCardAvailable: true,
      chosenFolder: onCard,
    );
    await _pump(tester, store);

    await tester.tap(find.text('SD card'));
    await tester.pumpAndSettle();

    expect(store.chosenKinds, <StorageVolumeKind>[StorageVolumeKind.sdCard]);
    expect(find.textContaining('SD card/Wallpapers/tela'), findsOneWidget);
  });

  testWidgets('backing out of the picker leaves the volume unchanged', (
    WidgetTester tester,
  ) async {
    // chosenFolder null == user cancelled or the card was gone.
    final FakeImageStore store = FakeImageStore(
      folder: onDevice,
      sdCardAvailable: true,
    );
    await _pump(tester, store);

    await tester.tap(find.text('SD card'));
    await tester.pumpAndSettle();

    expect(store.chosenKinds, <StorageVolumeKind>[StorageVolumeKind.sdCard]);
    // Still on the device folder it started with — a cancelled pick is a no-op.
    expect(_selectedKind(tester), StorageVolumeKind.device);
    expect(find.textContaining('Internal storage/tela'), findsOneWidget);
  });

  testWidgets('with nothing chosen yet, neither volume is selected', (
    WidgetTester tester,
  ) async {
    await _pump(tester, FakeImageStore());

    expect(_selectedKind(tester), isNull);
    expect(find.textContaining('will ask you to confirm'), findsOneWidget);
  });

  group('explicit-on-removable warning', () {
    // The second edge: NSFW already routes to files-outside-gallery, so
    // pointing that folder at a removable card is what tips explicit downloads
    // onto storage the private tier's protections cannot reach.
    FakeSettingsRepository nsfwOnFiles({bool acknowledged = false}) {
      return FakeSettingsRepository(
        settings: StorageSettings(
          sfwTier: StorageTier.filesOutsideGallery,
          nsfwTier: StorageTier.filesOutsideGallery,
        ),
        nsfwOnRemovableAcknowledged: acknowledged,
      );
    }

    testWidgets('warns when a removable card is chosen for explicit files', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        FakeImageStore(sdCardAvailable: true, chosenFolder: onCard),
        settings: nsfwOnFiles(),
      );

      await tester.tap(find.text('SD card'));
      await tester.pumpAndSettle();

      expect(
        find.text('Explicit downloads on a removable card'),
        findsOneWidget,
      );
    });

    testWidgets('using the card anyway persists the one-time nod', (
      WidgetTester tester,
    ) async {
      final FakeSettingsRepository settings = nsfwOnFiles();
      await _pump(
        tester,
        FakeImageStore(sdCardAvailable: true, chosenFolder: onCard),
        settings: settings,
      );

      await tester.tap(find.text('SD card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use card anyway'));
      await tester.pumpAndSettle();

      expect(settings.nsfwOnRemovableAckSaved, isTrue);
      // Explicit downloads stay on the files tier — the card is accepted.
      expect(settings.saved.nsfwTier, StorageTier.filesOutsideGallery);
    });

    testWidgets('declining routes explicit downloads to the private tier', (
      WidgetTester tester,
    ) async {
      final FakeSettingsRepository settings = nsfwOnFiles();
      await _pump(
        tester,
        FakeImageStore(sdCardAvailable: true, chosenFolder: onCard),
        settings: settings,
      );

      await tester.tap(find.text('SD card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use private library'));
      await tester.pumpAndSettle();

      // The card still serves safe downloads; explicit ones move off it.
      expect(settings.saved.nsfwTier, StorageTier.appPrivate);
      expect(settings.saved.sfwTier, StorageTier.filesOutsideGallery);
      expect(settings.nsfwOnRemovableAckSaved, isFalse);
    });

    testWidgets('an already-acknowledged card never warns again', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        FakeImageStore(sdCardAvailable: true, chosenFolder: onCard),
        settings: nsfwOnFiles(acknowledged: true),
      );

      await tester.tap(find.text('SD card'));
      await tester.pumpAndSettle();

      expect(
        find.text('Explicit downloads on a removable card'),
        findsNothing,
      );
    });

    testWidgets('a device folder for explicit files raises no warning', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        FakeImageStore(chosenFolder: onDevice),
        settings: nsfwOnFiles(),
      );

      await tester.tap(find.text('Internal storage'));
      await tester.pumpAndSettle();

      expect(
        find.text('Explicit downloads on a removable card'),
        findsNothing,
      );
    });
  });
}

StorageVolumeKind? _selectedKind(WidgetTester tester) {
  final RadioGroup<StorageVolumeKind> group = tester
      .widget<RadioGroup<StorageVolumeKind>>(
        find.byType(RadioGroup<StorageVolumeKind>),
      );
  return group.groupValue;
}

Future<void> _pump(
  WidgetTester tester,
  FakeImageStore store, {
  FakeSettingsRepository? settings,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        imageStoreProvider.overrideWithValue(store),
        settingsRepositoryProvider.overrideWithValue(
          settings ?? FakeSettingsRepository(),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: DownloadLocationSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
