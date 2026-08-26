import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';
import 'package:tela/domain/models/stored_image_size.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/features/settings/offload_screen.dart';

import '../fakes/fake_download_history.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_settings_repository.dart';

void main() {
  const DownloadFolder onCard = DownloadFolder(
    volumeLabel: 'SD card',
    relativePath: 'tela',
    isRemovable: true,
    isAvailable: true,
  );

  testWidgets('with no card in the slot it offers nothing but a reason', (
    WidgetTester tester,
  ) async {
    await _pump(tester, FakeImageStore(), _history(<String>['aaa']));

    expect(find.textContaining('No SD card found'), findsOneWidget);
    expect(find.byKey(const Key('offload-run')), findsNothing);
  });

  testWidgets('with a card but nothing to move it says so', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      FakeImageStore(sdCardAvailable: true),
      FakeDownloadHistory(),
    );

    expect(find.textContaining('Nothing to move'), findsOneWidget);
  });

  testWidgets('lists each group with what it would free', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      _storeWith(<String>['aaa', 'bbb']),
      _history(
        <String>['aaa', 'bbb'],
      ),
    );

    expect(find.text('In your gallery'), findsOneWidget);
    // 2 x 2 MB, formatted the way every storage figure in tela is.
    expect(find.text('4.0 MB freed'), findsOneWidget);
    expect(
      find.textContaining('2 wallpapers in Pictures/tela'),
      findsOneWidget,
    );
  });

  /// Two of the three groups change more than a location, so arriving
  /// pre-ticked would be one mis-tap away from a decision nobody made.
  testWidgets('nothing is ticked to begin with, and the button is dead', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _storeWith(<String>['aaa']), _history(<String>['aaa']));

    expect(find.text('Nothing selected'), findsOneWidget);
    expect(_runButton(tester).onPressed, isNull);
  });

  testWidgets('ticking a group adds its files and bytes to the tally', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _storeWith(<String>['aaa']), _history(<String>['aaa']));

    await tester.tap(
      find.byKey(const Key('offload-group-galleryDownloads')),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 file · 2.0 MB freed'), findsOneWidget);
    expect(_runButton(tester).onPressed, isNotNull);
  });

  testWidgets('the private library is a group of its own, warned about', (
    WidgetTester tester,
  ) async {
    final FakeImageStore store = FakeImageStore(
      sdCardAvailable: true,
      privateLibrary: <PrivateImage>[_private('ccc')],
    );

    await _pump(tester, store, FakeDownloadHistory());

    expect(find.text('Private library'), findsOneWidget);
    // Both halves of the honest sentence: the limit of what a dot buys, and
    // the reassurance that "hidden" does not mean "gone from the app".
    expect(find.textContaining('hidden folder'), findsOneWidget);
    expect(
      find.textContaining('in the private library'),
      findsOneWidget,
    );
  });

  testWidgets('running the move confirms, moves, and re-routes downloads', (
    WidgetTester tester,
  ) async {
    final FakeImageStore store = _storeWith(<String>['aaa'], folder: onCard);
    final FakeSettingsRepository settings = FakeSettingsRepository();
    await _pump(
      tester,
      store,
      _history(<String>['aaa']),
      settings: settings,
    );

    await _tickAndRun(tester);

    expect(find.textContaining('Move 1 file to the SD card?'), findsOneWidget);
    await tester.tap(find.text('Move to SD card').last);
    await tester.pumpAndSettle();

    expect(store.copies.single.tier, StorageTier.filesOutsideGallery);
    expect(settings.saved.sfwTier, StorageTier.filesOutsideGallery);
    // Untouched: the private library was not part of this move.
    expect(settings.saved.nsfwTier, StorageTier.appPrivate);
    // The finished panel confirms what actually happened to the setting,
    // not just what the pre-move copy promised.
    expect(
      find.text('New downloads will be saved here from now on.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('including explicit ones'),
      findsNothing,
    );
  });

  /// A copy that runs the card out of space stops partway and leaves the
  /// library split across two disks, so the room is checked before anything is
  /// copied and before the user is asked to commit.
  testWidgets('a card too small to hold the selection is refused', (
    WidgetTester tester,
  ) async {
    const DownloadFolder fullCard = DownloadFolder(
      volumeLabel: 'SD card',
      relativePath: 'tela',
      isRemovable: true,
      isAvailable: true,
      freeBytes: 1024,
    );
    final FakeImageStore store = _storeWith(<String>['aaa'], folder: fullCard);
    await _pump(tester, store, _history(<String>['aaa']));

    await _tickAndRun(tester);

    expect(find.textContaining('only 1 KB free'), findsOneWidget);
    expect(find.textContaining('Move 1 file to the SD card?'), findsNothing);
    expect(store.copies, isEmpty);
  });

  testWidgets('cancelling the confirmation moves nothing', (
    WidgetTester tester,
  ) async {
    final FakeImageStore store = _storeWith(<String>['aaa'], folder: onCard);
    await _pump(tester, store, _history(<String>['aaa']));

    await _tickAndRun(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(store.copies, isEmpty);
  });

  /// The grant has to come first: this tier cannot write without a tree, and
  /// finding that out after copying nothing is a wall with no explanation.
  testWidgets('with no card folder granted yet, the picker runs first', (
    WidgetTester tester,
  ) async {
    final FakeImageStore store = _storeWith(
      <String>['aaa'],
      chosenFolder: onCard,
    );
    await _pump(tester, store, _history(<String>['aaa']));

    await _tickAndRun(tester);

    expect(store.chosenKinds, <StorageVolumeKind>[StorageVolumeKind.sdCard]);
    expect(find.textContaining('Move 1 file to the SD card?'), findsOneWidget);
  });

  testWidgets('backing out of the folder picker never asks to confirm', (
    WidgetTester tester,
  ) async {
    // chosenFolder null == the user cancelled the system picker.
    final FakeImageStore store = _storeWith(<String>['aaa']);
    await _pump(tester, store, _history(<String>['aaa']));

    await _tickAndRun(tester);

    expect(find.textContaining('Move 1 file to the SD card?'), findsNothing);
    expect(store.copies, isEmpty);
  });

  testWidgets('moving the private library re-routes explicit downloads too', (
    WidgetTester tester,
  ) async {
    final FakeImageStore store = FakeImageStore(
      sdCardAvailable: true,
      folder: onCard,
      privateLibrary: <PrivateImage>[_private('ccc')],
    );
    final FakeSettingsRepository settings = FakeSettingsRepository();
    await _pump(tester, store, FakeDownloadHistory(), settings: settings);

    await tester.tap(find.byKey(const Key('offload-group-privateLibrary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('offload-run')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to SD card').last);
    await tester.pumpAndSettle();

    // Leaving it on the private tier would refill the disk that was just
    // cleared with exactly what came off it.
    expect(settings.saved.nsfwTier, StorageTier.filesOutsideGallery);
    // Explicit downloads moving is surprising enough to name outright, not
    // fold silently into a generic "downloads" notice.
    expect(
      find.textContaining('including explicit ones'),
      findsOneWidget,
    );
  });

  testWidgets('a run that moves nothing shows no future-downloads notice', (
    WidgetTester tester,
  ) async {
    // A card too small to hold anything never starts a run, so there is
    // nothing for the finished panel to confirm — this pins the guard at
    // OffloadProgressPanel._futureDownloadsNotice rather than assuming a
    // panel with moved == 0 never renders.
    const DownloadFolder fullCard = DownloadFolder(
      volumeLabel: 'SD card',
      relativePath: 'tela',
      isRemovable: true,
      isAvailable: true,
      freeBytes: 1024,
    );
    final FakeImageStore store = _storeWith(<String>['aaa'], folder: fullCard);
    await _pump(tester, store, _history(<String>['aaa']));

    await _tickAndRun(tester);

    expect(find.textContaining('will be saved here'), findsNothing);
  });
}

Future<void> _tickAndRun(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('offload-group-galleryDownloads')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('offload-run')));
  await tester.pumpAndSettle();
}

FilledButton _runButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('offload-run')));

/// A store holding a card and 2 MB of measurable gallery downloads per id.
FakeImageStore _storeWith(
  List<String> ids, {
  DownloadFolder? folder,
  DownloadFolder? chosenFolder,
}) {
  return FakeImageStore(
      sdCardAvailable: true,
      folder: folder,
      chosenFolder: chosenFolder,
    )
    ..sizes = <Uri, StoredImageSize>{
      for (final String id in ids)
        _locationOf(id): const StoredImageSize(
          bytes: 2097152,
          onRemovableVolume: false,
        ),
    };
}

FakeDownloadHistory _history(List<String> ids) => FakeDownloadHistory(
  initial: <DownloadRecord>[for (final String id in ids) _record(id)],
);

Uri _locationOf(String id) =>
    Uri.parse('content://media/external/images/media/$id');

DownloadRecord _record(String id) => DownloadRecord(
  wallpaper: _wallpaper(id),
  tier: StorageTier.sharedGallery,
  location: _locationOf(id),
  downloadedAt: DateTime(2026, 8, 25),
);

PrivateImage _private(String id) => PrivateImage(
  ref: WallpaperRef(SourceId.wallhaven, id),
  location: Uri.parse('file:///data/tela/wallhaven-$id.jpg'),
  savedAt: DateTime(2026, 8, 25),
  sizeBytes: 1048576,
);

Wallpaper _wallpaper(String id) => Wallpaper(
  id: id,
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
  fullImageUrl: 'https://w.wallhaven.cc/full/$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/$id.jpg',
  resolution: const Resolution(1080, 2400),
  fileSizeBytes: 1024,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);

Future<void> _pump(
  WidgetTester tester,
  FakeImageStore store,
  FakeDownloadHistory history, {
  FakeSettingsRepository? settings,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        imageStoreProvider.overrideWithValue(store),
        downloadHistoryProvider.overrideWithValue(history),
        settingsRepositoryProvider.overrideWithValue(
          settings ?? FakeSettingsRepository(),
        ),
      ],
      child: const MaterialApp(
        home: OffloadScreen(),
        localizationsDelegates: <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
