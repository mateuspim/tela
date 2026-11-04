import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/justified_wallpaper_grid.dart';
import 'package:tela/core/ui/wallpaper_selection.dart';
import 'package:tela/core/ui/wallpaper_source_badge.dart';
import 'package:tela/core/ui/wallpaper_source_labels_scope.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/library_order.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/local_preview_cache.dart';
import 'package:tela/features/private_library/private_library_screen.dart';

import '../fakes/fake_app_lock.dart';
import '../fakes/fake_download_history.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_local_preview_cache.dart';
import '../fakes/fake_screen_guard.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/gated_local_preview_cache.dart';

void main() {
  group('FLAG_SECURE', () {
    testWidgets('is held for as long as the private library is open', (
      WidgetTester tester,
    ) async {
      final FakeScreenGuard guard = FakeScreenGuard();
      await _pump(tester, FakeImageStore(), guard: guard);

      expect(
        guard.isSecure,
        isTrue,
        reason: 'an explicit wallpaper must never reach the app switcher',
      );
    });

    testWidgets('is released when the library is left', (
      WidgetTester tester,
    ) async {
      final FakeScreenGuard guard = FakeScreenGuard();
      await _pump(tester, FakeImageStore(), guard: guard);

      // Replacing the route disposes the screen, as popping it would.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(
        guard.isSecure,
        isFalse,
        reason: 'leaving it on would block screenshots of the whole app',
      );
      expect(guard.requests, <bool>[true, false]);
    });
  });

  group('app-lock', () {
    testWidgets('lists nothing until the lock is satisfied', (
      WidgetTester tester,
    ) async {
      final FakeAppLock lock = FakeAppLock(passes: false);
      await _pump(
        tester,
        FakeImageStore(privateLibrary: <PrivateImage>[_image('e7jvjd')]),
        lock: lock,
        locked: true,
      );

      expect(lock.prompts, 1);
      expect(find.text('The private library is locked.'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Private wallpaper e7jvjd'),
        findsNothing,
        reason: 'a failed prompt must not leave the contents on screen',
      );
    });

    testWidgets('opens once the prompt passes', (WidgetTester tester) async {
      final FakeAppLock lock = FakeAppLock();
      await _pump(
        tester,
        FakeImageStore(privateLibrary: <PrivateImage>[_image('e7jvjd')]),
        lock: lock,
        locked: true,
      );

      expect(lock.prompts, 1);
      expect(find.bySemanticsLabel('Private wallpaper e7jvjd'), findsOneWidget);
    });

    testWidgets('a dismissed prompt can be retried', (
      WidgetTester tester,
    ) async {
      final FakeAppLock lock = FakeAppLock(passes: false);
      await _pump(tester, FakeImageStore(), lock: lock, locked: true);

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(lock.prompts, 2);
    });

    testWidgets('does not prompt when the lock is off', (
      WidgetTester tester,
    ) async {
      final FakeAppLock lock = FakeAppLock();
      await _pump(tester, FakeImageStore(), lock: lock);

      expect(lock.prompts, 0);
      expect(find.textContaining('Nothing here'), findsOneWidget);
    });

    testWidgets('stays shut when the device cannot ask for anything', (
      WidgetTester tester,
    ) async {
      // Regression, found on hardware 2026-07-14. This used to open the library
      // outright: an unavailable lock was read as "this device has no
      // credentials at all", and the gate stepped aside rather than trap the
      // owner outside their own files. But `isAvailable` reports a *locked-out
      // sensor* the same way — so on a device whose only credential is a
      // fingerprint, five bad reads opened the private library to anyone.
      // The gate now fails closed, and the way back in is the Settings switch.
      final FakeAppLock lock = FakeAppLock(available: false, passes: false);
      await _pump(
        tester,
        FakeImageStore(privateLibrary: <PrivateImage>[_image('e7jvjd')]),
        lock: lock,
        locked: true,
      );

      expect(find.bySemanticsLabel('Private wallpaper e7jvjd'), findsNothing);
      expect(find.textContaining('locked'), findsWidgets);
    });
  });

  group('PrivateLibraryScreen', () {
    testWidgets('explains itself when the tier is empty', (
      WidgetTester tester,
    ) async {
      await _pump(tester, FakeImageStore());

      expect(find.textContaining('Nothing here'), findsOneWidget);
    });

    testWidgets('renders a tile per app-private image', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        FakeImageStore(
          privateLibrary: <PrivateImage>[_image('newer'), _image('older')],
        ),
      );

      expect(find.bySemanticsLabel('Private wallpaper newer'), findsOneWidget);
      expect(find.bySemanticsLabel('Private wallpaper older'), findsOneWidget);
    });

    testWidgets('deleting from a selection happens only once confirmed', (
      WidgetTester tester,
    ) async {
      // A long press now enters multi-select rather than asking outright, so
      // deleting one file is the batch delete at a count of one. The
      // permanence warning is the thing that must survive that move — it is
      // the only warning the user gets before a file is gone for good.
      final FakeImageStore store = FakeImageStore(
        privateLibrary: <PrivateImage>[_image('e7jvjd')],
      );
      await _pump(tester, store);

      await _deleteSelected(tester);
      expect(find.text('Delete this wallpaper?'), findsOneWidget);
      expect(
        find.textContaining('This cannot be undone'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(store.deletedRefs, isEmpty, reason: 'a deletion is not undoable');
      // The cancelled dialog leaves the tick alone: the user cancelled the
      // deletion, not the selection.
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(
        store.deletedRefs,
        <WallpaperRef>[const WallpaperRef(SourceId.wallhaven, 'e7jvjd')],
      );
      expect(find.textContaining('Nothing here'), findsOneWidget);
    });

    testWidgets('moving out warns it never reaches Photos, and is untracked', (
      WidgetTester tester,
    ) async {
      // Two surprises this move holds, and the copy has to say both before it
      // happens: it cannot go to Photos (tela cannot prove a private image is
      // safe to show there), and the image leaves every tela screen — there is
      // no wallpaper left to write a history row from.
      final FakeImageStore store = FakeImageStore(
        privateLibrary: <PrivateImage>[_image('e7jvjd')],
        folder: _grantedFolder,
      );
      await _pump(tester, store);

      await _moveOutSelected(tester);

      expect(
        find.textContaining('Move this out of the private library?'),
        findsOneWidget,
      );
      expect(find.textContaining('never to Photos'), findsOneWidget);
      expect(find.textContaining('stops tracking it'), findsOneWidget);
      expect(store.copies, isEmpty, reason: 'the dialog alone moves nothing');
    });

    testWidgets('a confirmed move out lands in the files tier, never Photos', (
      WidgetTester tester,
    ) async {
      // The invariant this whole direction rests on: the move declares `nsfw`
      // because it cannot prove otherwise, and the store refuses the gallery.
      final FakeImageStore store = FakeImageStore(
        privateLibrary: <PrivateImage>[_image('e7jvjd')],
        folder: _grantedFolder,
      );
      await _pump(tester, store);

      await _moveOutSelected(tester);
      await tester.tap(find.text('Move out').last);
      await tester.pumpAndSettle();

      expect(store.copies.single.tier, StorageTier.filesOutsideGallery);
      expect(
        store.deletedTiers,
        <StorageTier>[StorageTier.appPrivate],
      );
      expect(find.text('Moved to your downloads folder'), findsOneWidget);
      expect(find.textContaining('Nothing here'), findsOneWidget);
    });

    testWidgets('moving out with no folder yet runs the volume chooser', (
      WidgetTester tester,
    ) async {
      // That tier needs a granted folder, and finding that out after copying
      // nothing is a wall with no explanation. Backing out moves nothing.
      final FakeImageStore store = FakeImageStore(
        privateLibrary: <PrivateImage>[_image('e7jvjd')],
      );
      await _pump(tester, store);

      await _moveOutSelected(tester);
      await tester.tap(find.text('Move out').last);
      await tester.pumpAndSettle();

      expect(find.text('Where files are saved'), findsOneWidget);
      expect(find.text('Internal storage'), findsOneWidget);
      expect(store.copies, isEmpty);
    });

    testWidgets('a ticked private tile shows the selection it is in', (
      WidgetTester tester,
    ) async {
      // The bug this pins: the private grid drew its own tile and so never wore
      // the wash-and-tick every other shelf has, leaving a selection you could
      // make but not see. One shared overlay now, drawn from one id.
      final FakeImageStore store = FakeImageStore(
        privateLibrary: <PrivateImage>[_image('e7jvjd'), _image('7j1mzo')],
      );
      await _pump(tester, store);

      // The overlay sits on every tile from the start and draws nothing until
      // the shelf is selecting, so it is the tick that says the mode changed.
      expect(find.byType(WallpaperSelectionOverlay), findsNWidgets(2));
      expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);

      await tester.longPress(find.bySemanticsLabel('Private wallpaper e7jvjd'));
      await tester.pumpAndSettle();

      // Every tile now shows a mark — the empty circles are what say the whole
      // shelf changed mode — but only the ticked one draws a check.
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    });

    testWidgets('says so, without naming a path, when it cannot be read', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        FakeImageStore(
          failure: const ImageStoreFailure(ImageStoreProblem.unavailable),
        ),
      );

      expect(find.text("Couldn't open the private library."), findsOneWidget);
    });
  });

  group('vault tiles', () {
    // Regression: a vault (SAF) location is a `content:` URI, and Image.file
    // cannot decode one directly — `File.fromUri` throws before the frame is
    // even built, which in a release build renders as a bare grey box. These
    // pin that a vault tile instead resolves its own thumbnail and draws it.
    testWidgets('resolves and draws a thumbnail for a vault image', (
      WidgetTester tester,
    ) async {
      final PrivateImage vault = _vaultImage('e7jvjd');
      final FakeLocalPreviewCache previews = FakeLocalPreviewCache(
        bounds: <Uri, ({int width, int height})>{
          vault.location: (width: 1080, height: 2400),
        },
      );

      await _pump(
        tester,
        FakeImageStore(privateLibrary: <PrivateImage>[vault]),
        previews: previews,
      );

      expect(previews.thumbnailsRequested, <Uri>[vault.location]);
      expect(find.bySemanticsLabel('Private wallpaper e7jvjd'), findsOneWidget);
      // The fixture's path is not a real file, so the decode itself is out of
      // scope here (see private_immersive_session_test.dart for the same
      // choice) — what this pins is that resolving one never crashes the tile.
      expect(tester.takeException(), isNull);
    });

    testWidgets('draws a broken-image state rather than crash', (
      WidgetTester tester,
    ) async {
      // No bounds fixture for this location, so the fake answers null — the
      // same reading a corrupt or unreadable file gets on device.
      final PrivateImage vault = _vaultImage('e7jvjd');

      await _pump(
        tester,
        FakeImageStore(privateLibrary: <PrivateImage>[vault]),
        previews: FakeLocalPreviewCache(),
      );

      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });

    testWidgets('asks for a thumbnail at most once per image', (
      WidgetTester tester,
    ) async {
      final PrivateImage vault = _vaultImage('e7jvjd');
      final FakeLocalPreviewCache previews = FakeLocalPreviewCache(
        bounds: <Uri, ({int width, int height})>{
          vault.location: (width: 1080, height: 2400),
        },
      );

      await _pump(
        tester,
        FakeImageStore(privateLibrary: <PrivateImage>[vault]),
        previews: previews,
      );
      // The resolved thumbnail's aspect ratio feeds back into the grid, which
      // repacks and rebuilds this tile again — a second request here would be
      // the whole point of caching by location silently regressing.
      await tester.longPress(find.bySemanticsLabel('Private wallpaper e7jvjd'));
      await tester.pumpAndSettle();

      expect(previews.thumbnailsRequested, <Uri>[vault.location]);
    });

    testWidgets('an app-private tile asks for a persisted thumbnail once', (
      WidgetTester tester,
    ) async {
      // Regression (owner, 2026-11-04): it used to decode the original with
      // Image.file(cacheWidth:) on every visit, ~30s for a big library.
      final FakeLocalPreviewCache previews = FakeLocalPreviewCache(
        fallbackBounds: (width: 4, height: 3),
      );
      final PrivateImage image = _image('e7jvjd');

      await _pump(
        tester,
        FakeImageStore(privateLibrary: <PrivateImage>[image]),
        previews: previews,
      );

      expect(previews.thumbnailsRequested, <Uri>[image.location]);
    });

    testWidgets('a late thumbnail paints without rebuilding the screen', (
      WidgetTester tester,
    ) async {
      // Regression (owner, device pass 2026-11-04): every resolved thumbnail
      // rebuilt the whole 7,298-image screen; tiles stayed blank until
      // scrolled. The tile now paints its own answer.
      final GatedLocalPreviewCache previews = GatedLocalPreviewCache();
      final PrivateImage image = _sizedImage('e7jvjd');

      await _pump(
        tester,
        FakeImageStore(privateLibrary: <PrivateImage>[image]),
        previews: previews,
      );
      expect(_thumbnailPaths(tester), isEmpty);
      final Widget gridBefore = tester.widget(
        find.byType(JustifiedWallpaperGrid),
      );

      previews.finish(image.location);
      // The await resolves on the first frame and the tile paints on the next.
      await tester.pump();
      await tester.pump();

      // The same grid instance: the screen did not rebuild (and re-pack every
      // row) for a thumbnail whose ratio the listing already knew.
      expect(
        identical(
          tester.widget(find.byType(JustifiedWallpaperGrid)),
          gridBefore,
        ),
        isTrue,
      );
      expect(_thumbnailPaths(tester), <String>[
        '/thumb/${image.location.path}',
      ]);
    });

    testWidgets("switching tag never leaves the last tag's pictures", (
      WidgetTester tester,
    ) async {
      // Regression (owner, device pass 2026-11-04): a tile reused at the same
      // grid position kept the previous tag's thumbnail, and never asked for
      // its new image's, until it was scrolled away and back.
      final GatedLocalPreviewCache previews = GatedLocalPreviewCache();
      final PrivateImage ana = _sizedImage('aaaaaa', tag: 'ana');
      final PrivateImage bia = _sizedImage('bbbbbb', tag: 'bia');

      await _pump(
        tester,
        FakeImageStore(privateLibrary: <PrivateImage>[ana, bia]),
        previews: previews,
      );
      // Only the first tag's picture has landed when the user switches, as on
      // a library still filling in.
      previews.finish(ana.location);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'bia'));
      await tester.pumpAndSettle();
      expect(_thumbnailPaths(tester), isEmpty);

      previews.finish(previews.started.last);
      await tester.pumpAndSettle();
      expect(_thumbnailPaths(tester), <String>['/thumb/${bia.location.path}']);
    });
  });

  group('order', () {
    // Owner, 2026-11-04: "we dont have a way to sort them by most recent first
    // or oldest". Newest first stays the default; the menu flips it and the
    // choice is saved.
    final PrivateImage older = _savedAt('aaaaaa', DateTime.utc(2026));
    final PrivateImage newer = _savedAt('bbbbbb', DateTime.utc(2026, 6));

    testWidgets('lists newest first by default', (WidgetTester tester) async {
      await _pump(
        tester,
        FakeImageStore(privateLibrary: <PrivateImage>[older, newer]),
      );

      expect(_tileOrder(tester), <String>['bbbbbb', 'aaaaaa']);
    });

    testWidgets('choosing oldest first reorders the grid and saves it', (
      WidgetTester tester,
    ) async {
      final FakeSettingsRepository settings = FakeSettingsRepository();
      await _pump(
        tester,
        FakeImageStore(privateLibrary: <PrivateImage>[older, newer]),
        settings: settings,
      );

      await tester.tap(find.byTooltip('Order: Newest first'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oldest first'));
      await tester.pumpAndSettle();

      expect(_tileOrder(tester), <String>['aaaaaa', 'bbbbbb']);
      expect(settings.privateLibraryOrder, LibraryOrder.oldestFirst);
    });
  });

  group('source badge', () {
    testWidgets('a private tile names the source its file came from', (
      WidgetTester tester,
    ) async {
      // The one library grid the badge did not reach, because `PrivateImage`
      // carried a bare id: this tier writes no history row, so its source had
      // nowhere to live until the file name started carrying it.
      await _pump(
        tester,
        FakeImageStore(
          privateLibrary: <PrivateImage>[
            _image('406484', source: SourceId.konachan),
            _image('e7jvjd'),
          ],
        ),
        labels: const <String, String>{
          'wallhaven': 'Wallhaven',
          'konachan': 'Konachan',
        },
      );

      expect(find.text('Konachan'), findsOneWidget);
      expect(find.text('Wallhaven'), findsOneWidget);
    });

    testWidgets('the badge is unconditional here, unlike the browse wall', (
      WidgetTester tester,
    ) async {
      // No `showSourceBadge` flag on this grid: the private tier is mixed by
      // nature — one folder holding whatever any source sent it — so there is
      // no single-source case for a badge to say nothing in.
      await _pump(
        tester,
        FakeImageStore(privateLibrary: <PrivateImage>[_image('e7jvjd')]),
        labels: const <String, String>{'wallhaven': 'Wallhaven'},
      );

      expect(find.byType(WallpaperSourceBadge), findsOneWidget);
    });

    testWidgets('a screen reader hears where the wallpaper came from', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        FakeImageStore(
          privateLibrary: <PrivateImage>[
            _image('406484', source: SourceId.konachan),
          ],
        ),
        labels: const <String, String>{'konachan': 'Konachan'},
      );

      expect(find.bySemanticsLabel('From Konachan'), findsOneWidget);
    });

    testWidgets('an unnamed source draws no badge rather than a raw id', (
      WidgetTester tester,
    ) async {
      // A file left by a build whose source this one has since retired. The
      // no-scope case is the same claim: the tile must still draw.
      await _pump(
        tester,
        FakeImageStore(
          privateLibrary: <PrivateImage>[
            _image('12345', source: const SourceId('yandere')),
          ],
        ),
        labels: const <String, String>{'wallhaven': 'Wallhaven'},
      );

      expect(find.byType(WallpaperSourceBadge), findsNothing);
      expect(find.text('yandere'), findsNothing);
      expect(
        find.bySemanticsLabel('Private wallpaper 12345'),
        findsOneWidget,
        reason: 'an unknown source must cost the badge, not the tile',
      );
    });
  });
}

/// Mounts the screen. [labels] stands in for the root-level scope `app.dart`
/// wires from the source registry; omitting it is the no-scope case, which must
/// draw no badge rather than throw.
Future<void> _pump(
  WidgetTester tester,
  FakeImageStore store, {
  FakeScreenGuard? guard,
  FakeAppLock? lock,
  bool locked = false,
  Map<String, String>? labels,
  LocalPreviewCache? previews,
  FakeSettingsRepository? settings,
}) async {
  const Widget screen = PrivateLibraryScreen();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        imageStoreProvider.overrideWithValue(store),
        downloadHistoryProvider.overrideWithValue(FakeDownloadHistory()),
        screenGuardProvider.overrideWithValue(guard ?? FakeScreenGuard()),
        appLockProvider.overrideWithValue(lock ?? FakeAppLock()),
        settingsRepositoryProvider.overrideWithValue(
          settings ?? FakeSettingsRepository(privateLibraryLocked: locked),
        ),
        localPreviewCacheProvider.overrideWithValue(
          previews ??
              FakeLocalPreviewCache(fallbackBounds: (width: 4, height: 3)),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: labels == null
            ? screen
            : WallpaperSourceLabelsScope(labels: labels, child: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PrivateImage _image(String id, {SourceId source = SourceId.wallhaven}) =>
    PrivateImage(
      ref: WallpaperRef(source, id),
      location: Uri.file(
        '/data/user/0/cc.pym.tela/files/wallpapers/${source.value}-$id.jpg',
      ),
      savedAt: DateTime.utc(2026, 7, 14),
      sizeBytes: 2048,
    );

/// A file the offload moved onto the card — a SAF document, not a plain path,
/// and the case the app-private fixture above cannot stand in for.
PrivateImage _vaultImage(String id, {SourceId source = SourceId.wallhaven}) =>
    PrivateImage(
      ref: WallpaperRef(source, id),
      location: Uri.parse(
        'content://com.android.externalstorage.documents/tree/'
        '1234-5678%3ATela/document/1234-5678%3ATela%2F${source.value}-$id.jpg',
      ),
      savedAt: DateTime.utc(2026, 7, 14),
      sizeBytes: 2048,
      tier: StorageTier.filesOutsideGallery,
    );

/// Long-presses the private tile into selection, then asks to delete it.
Future<void> _deleteSelected(WidgetTester tester) async {
  await tester.longPress(find.bySemanticsLabel('Private wallpaper e7jvjd'));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.delete_outline));
  await tester.pumpAndSettle();
}

/// The same, for the move-out action beside it.
Future<void> _moveOutSelected(WidgetTester tester) async {
  await tester.longPress(find.bySemanticsLabel('Private wallpaper e7jvjd'));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.lock_open_outlined));
  await tester.pumpAndSettle();
}

/// A folder already granted, so a move out needs no chooser.
const DownloadFolder _grantedFolder = DownloadFolder(
  volumeLabel: 'Internal storage',
  relativePath: 'Wallpapers/tela',
  isRemovable: false,
  isAvailable: true,
);

/// An app-private file whose bounds the listing already knows, as on device.
PrivateImage _sizedImage(String id, {String? tag}) => PrivateImage(
  ref: WallpaperRef(SourceId.wallhaven, id),
  location: Uri.file(
    '/data/user/0/cc.pym.tela/files/wallpapers/wallhaven-$id.jpg',
  ),
  savedAt: DateTime.utc(2026, 7, 14),
  sizeBytes: 2048,
  tag: tag == null ? null : TagFolder(tag),
  width: 1080,
  height: 2400,
);

/// The file paths of every thumbnail picture currently drawn.
List<String> _thumbnailPaths(WidgetTester tester) => <String>[
  for (final Image image in tester.widgetList<Image>(find.byType(Image)))
    if (image.image is FileImage) (image.image as FileImage).file.path,
];

/// An app-private image saved at [savedAt], to pin the library's order.
PrivateImage _savedAt(String id, DateTime savedAt) => PrivateImage(
  ref: WallpaperRef(SourceId.wallhaven, id),
  location: Uri.file(
    '/data/user/0/cc.pym.tela/files/wallpapers/wallhaven-$id.jpg',
  ),
  savedAt: savedAt,
  sizeBytes: 2048,
  width: 1080,
  height: 2400,
);

/// The ids of the private tiles in reading order: by row, then left to right.
List<String> _tileOrder(WidgetTester tester) {
  final Finder tiles = find.bySemanticsLabel(RegExp('^Private wallpaper '));
  final List<Element> found = tiles.evaluate().toList()
    ..sort((Element a, Element b) {
      final Offset pa = tester.getTopLeft(
        find.byElementPredicate((e) => e == a),
      );
      final Offset pb = tester.getTopLeft(
        find.byElementPredicate((e) => e == b),
      );
      return pa.dy != pb.dy ? pa.dy.compareTo(pb.dy) : pa.dx.compareTo(pb.dx);
    });
  return <String>[
    for (final Element e in found)
      (e.widget as Semantics).properties.label!.split(' ').last,
  ];
}
