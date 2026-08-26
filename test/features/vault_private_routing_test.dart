import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/move_to_private_action.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

import '../fakes/fake_download_history.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_settings_repository.dart';

/// What the private library's two homes mean for the actions over them.
///
/// The library lists the app-private tier and the hidden vault side by side and
/// they render identically, so every action that used to assume one tier now
/// has to read the image's own. The dangerous one is the move *out*: for a
/// vault image the destination is the tier it is already in, which would have
/// the copy resolve onto the document it is reading and the delete then remove
/// the file it just wrote.
void main() {
  testWidgets('an app-private image still moves out to the files folder', (
    WidgetTester tester,
  ) async {
    final FakeImageStore store = _store();
    await _pumpAndMoveOut(tester, store, <PrivateImage>[_image('aaa')]);

    expect(store.copies.single.tier, StorageTier.filesOutsideGallery);
  });

  testWidgets('a vault image is never copied onto itself', (
    WidgetTester tester,
  ) async {
    final FakeImageStore store = _store();
    await _pumpAndMoveOut(tester, store, <PrivateImage>[
      _image('aaa', tier: StorageTier.filesOutsideGallery),
    ]);

    expect(store.copies, isEmpty);
    expect(store.deletedLocations, isEmpty);
  });

  testWidgets('an all-vault selection never even asks', (
    WidgetTester tester,
  ) async {
    final FakeImageStore store = _store();
    await _pumpAndMoveOut(
      tester,
      store,
      <PrivateImage>[_image('aaa', tier: StorageTier.filesOutsideGallery)],
      confirm: false,
    );

    expect(find.textContaining('out of the private library'), findsNothing);
  });

  /// A mixed selection still does the half it can, rather than refusing whole:
  /// the honest tally is what every other batch in tela reports.
  testWidgets('a mixed selection moves the app-private half', (
    WidgetTester tester,
  ) async {
    final FakeImageStore store = _store();
    await _pumpAndMoveOut(tester, store, <PrivateImage>[
      _image('aaa'),
      _image('bbb', tier: StorageTier.filesOutsideGallery),
    ]);

    expect(
      <String>[
        for (final ({
              Uri from,
              StorageTier tier,
              TagFolder? tag,
              WallpaperRef ref,
            })
            copy
            in store.copies)
          copy.ref.id,
      ],
      <String>['aaa'],
    );
  });
}

FakeImageStore _store() => FakeImageStore(
  folder: const DownloadFolder(
    volumeLabel: 'SD card',
    relativePath: 'tela',
    isRemovable: true,
    isAvailable: true,
  ),
  sdCardAvailable: true,
);

PrivateImage _image(String id, {StorageTier tier = StorageTier.appPrivate}) =>
    PrivateImage(
      ref: WallpaperRef(SourceId.wallhaven, id),
      location: Uri.parse('file:///data/tela/wallhaven-$id.jpg'),
      savedAt: DateTime(2026, 8, 25),
      sizeBytes: 1024,
      tier: tier,
    );

/// Pumps a button that runs the move, taps it, and answers the confirmation.
Future<void> _pumpAndMoveOut(
  WidgetTester tester,
  FakeImageStore store,
  List<PrivateImage> images, {
  bool confirm = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        imageStoreProvider.overrideWithValue(store),
        downloadHistoryProvider.overrideWithValue(FakeDownloadHistory()),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) => TextButton(
              onPressed: () => confirmAndMoveOutOfPrivate(
                context: context,
                ref: ref,
                images: images,
              ),
              child: const Text('go'),
            ),
          ),
        ),
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  if (!confirm) return;
  final Finder action = find.text('Move out');
  if (action.evaluate().isEmpty) return;
  await tester.tap(action);
  await tester.pumpAndSettle();
}
