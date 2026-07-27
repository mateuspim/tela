import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_selection.dart';
import 'package:tela/core/ui/wallpaper_source_badge.dart';
import 'package:tela/core/ui/wallpaper_source_labels_scope.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/features/private_library/private_library_screen.dart';

import '../fakes/fake_app_lock.dart';
import '../fakes/fake_download_history.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_screen_guard.dart';
import '../fakes/fake_settings_repository.dart';

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
          FakeSettingsRepository(privateLibraryLocked: locked),
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
