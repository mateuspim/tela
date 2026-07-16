import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/features/private_library/private_immersive_session.dart';

import '../fakes/fake_app_lock.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_immersive_system_ui.dart';
import '../fakes/fake_local_preview_cache.dart';
import '../fakes/fake_screen_guard.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_wallpaper_applier.dart';

void main() {
  group('app-lock', () {
    testWidgets('shows nothing until the lock passes, but stays secure', (
      WidgetTester tester,
    ) async {
      final FakeAppLock lock = FakeAppLock(passes: false);
      final FakeScreenGuard guard = FakeScreenGuard();
      await _open(
        tester,
        _session(<PrivateImage>[_image('e7jvjd')]),
        lock: lock,
        guard: guard,
        locked: true,
      );

      expect(lock.prompts, 1);
      expect(find.byKey(const Key('private-viewer-set')), findsNothing);
      expect(find.text('The private library is locked.'), findsOneWidget);
      expect(
        guard.isSecure,
        isTrue,
        reason: 'a gated viewer is still a secure window',
      );
    });

    testWidgets('opens the viewer once the prompt passes', (
      WidgetTester tester,
    ) async {
      final FakeAppLock lock = FakeAppLock();
      await _open(
        tester,
        _session(<PrivateImage>[_image('e7jvjd')]),
        lock: lock,
        locked: true,
      );

      expect(lock.prompts, 1);
      expect(find.byKey(const Key('private-viewer-set')), findsOneWidget);
    });

    testWidgets('swiping does not re-run authentication', (
      WidgetTester tester,
    ) async {
      final FakeAppLock lock = FakeAppLock();
      final GallerySessionController<PrivateImage> session = _session(
        <PrivateImage>[_image('newer'), _image('older')],
      );
      await _open(tester, session, lock: lock, locked: true);

      await tester.tap(find.byKey(const Key('immersive-viewer-next')));
      await tester.pumpAndSettle();

      expect(session.selectedIndex, 1);
      expect(
        lock.prompts,
        1,
        reason: 'the lock is a per-entry toll, not per-swipe',
      );
    });
  });

  group('FLAG_SECURE', () {
    testWidgets('is acquired before content and held through the whole flow', (
      WidgetTester tester,
    ) async {
      final FakeScreenGuard guard = FakeScreenGuard();
      await _open(
        tester,
        _session(<PrivateImage>[_image('e7jvjd')]),
        guard: guard,
      );

      expect(guard.requests.first, isTrue, reason: 'claimed before any pixels');
      expect(guard.isSecure, isTrue);

      // Into the target sheet: still secure.
      await tester.tap(find.byKey(const Key('private-viewer-set')));
      await tester.pumpAndSettle();
      expect(find.text('Set wallpaper on'), findsOneWidget);
      expect(guard.isSecure, isTrue);
      await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
      await tester.pumpAndSettle();

      // Into the delete confirmation: still secure.
      await tester.tap(find.byKey(const Key('private-viewer-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this wallpaper?'), findsOneWidget);
      expect(guard.isSecure, isTrue);
    });

    testWidgets('is released when the viewer is disposed', (
      WidgetTester tester,
    ) async {
      final FakeScreenGuard guard = FakeScreenGuard();
      await _open(
        tester,
        _session(<PrivateImage>[_image('e7jvjd')]),
        guard: guard,
      );
      expect(guard.isSecure, isTrue);

      // Tearing down the tree disposes the viewer, as popping the route would.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(
        guard.isSecure,
        isFalse,
        reason: 'leaving the private flow gives the window flag back',
      );
      expect(guard.requests, <bool>[true, false]);
    });
  });

  testWidgets('offers no way to share a private image', (
    WidgetTester tester,
  ) async {
    await _open(tester, _session(<PrivateImage>[_image('e7jvjd')]));

    expect(find.byIcon(Icons.share), findsNothing);
    expect(find.byIcon(Icons.ios_share), findsNothing);
    expect(find.byType(PopupMenuButton<void>), findsNothing);
    // The one feature action is delete.
    expect(find.byKey(const Key('private-viewer-delete')), findsOneWidget);
  });

  testWidgets('Set applies the shown private file through the applier', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperApplier applier = FakeWallpaperApplier();
    await _open(
      tester,
      _session(<PrivateImage>[_image('e7jvjd')]),
      applier: applier,
    );

    await tester.tap(find.byKey(const Key('private-viewer-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home and lock screens'));
    await tester.pumpAndSettle();

    expect(applier.receivedSources, <Uri>[_location('e7jvjd')]);
    expect(applier.receivedTarget, WallpaperTarget.both);
    expect(find.text('Wallpaper set.'), findsOneWidget);
  });

  testWidgets('the position announcement never carries a path', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      _session(<PrivateImage>[_image('newer'), _image('older')]),
    );

    expect(find.bySemanticsLabel('1 of 2'), findsOneWidget);
    // Nothing on screen names the file or where it lives.
    expect(find.textContaining('wallhaven-'), findsNothing);
    expect(find.textContaining('/data/'), findsNothing);
    expect(find.textContaining('.jpg'), findsNothing);
  });

  testWidgets('a corrupt file renders a safe broken state without crashing', (
    WidgetTester tester,
  ) async {
    final PrivateImage corrupt = _image('corrupt', width: null, height: null);
    await _open(
      tester,
      _session(<PrivateImage>[corrupt]),
      cache: FakeLocalPreviewCache(unreadable: <Uri>{corrupt.location}),
    );

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete advances to next, then previous, then closes to empty', (
    WidgetTester tester,
  ) async {
    final FakeImageStore store = FakeImageStore(
      privateLibrary: <PrivateImage>[
        _image('a'),
        _image('b'),
        _image('c'),
      ],
    );
    // Positioned on the middle image.
    await _open(
      tester,
      _session(
        <PrivateImage>[_image('a'), _image('b'), _image('c')],
        initialIndex: 1,
      ),
      store: store,
    );

    // Delete 'b': 'c' slides up into its place — the next image, now last.
    await _confirmDelete(tester);
    expect(store.deletedIds, <String>['b']);
    expect(find.bySemanticsLabel('Private wallpaper c'), findsWidgets);
    expect(find.bySemanticsLabel('2 of 2'), findsOneWidget);

    // Delete 'c' at the end: selection clamps back to 'a', the previous.
    await _confirmDelete(tester);
    expect(store.deletedIds, <String>['b', 'c']);
    expect(find.bySemanticsLabel('Private wallpaper a'), findsWidgets);

    // Delete the last one: the viewer closes back to the grid stand-in.
    await _confirmDelete(tester);
    expect(store.deletedIds, <String>['b', 'c', 'a']);
    expect(find.text('grid'), findsOneWidget);
    expect(find.byType(PrivateImmersiveSession), findsNothing);
  });

  // The close button was inherited from History and dead on the tablet: onClose
  // called maybePop(), which consulted the viewer's own PopScope before its
  // canPop rebuild had landed, so the exit re-entered itself and nothing
  // popped. The bug is inherited, so History pins this separately.
  testWidgets('the close button pops the viewer back to the grid', (
    WidgetTester tester,
  ) async {
    await _open(tester, _session(<PrivateImage>[_image('a')]));
    expect(find.byType(PrivateImmersiveSession), findsOneWidget);

    await tester.tap(find.byKey(const Key('immersive-viewer-close')));
    await tester.pumpAndSettle();

    expect(find.byType(PrivateImmersiveSession), findsNothing);
    expect(find.text('grid'), findsOneWidget);
  });
}

Future<void> _confirmDelete(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('private-viewer-delete')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
  await tester.pumpAndSettle();
}

Future<void> _open(
  WidgetTester tester,
  GallerySessionController<PrivateImage> session, {
  FakeAppLock? lock,
  FakeScreenGuard? guard,
  FakeImageStore? store,
  FakeWallpaperApplier? applier,
  FakeLocalPreviewCache? cache,
  bool locked = false,
}) async {
  addTearDown(session.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appLockProvider.overrideWithValue(lock ?? FakeAppLock()),
        screenGuardProvider.overrideWithValue(guard ?? FakeScreenGuard()),
        imageStoreProvider.overrideWithValue(store ?? FakeImageStore()),
        wallpaperApplierProvider.overrideWithValue(
          applier ?? FakeWallpaperApplier(),
        ),
        localPreviewCacheProvider.overrideWithValue(
          cache ?? FakeLocalPreviewCache(),
        ),
        settingsRepositoryProvider.overrideWithValue(
          FakeSettingsRepository(privateLibraryLocked: locked),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        // The viewer is pushed over a grid stand-in so its FLAG_SECURE and lock
        // are exercised independently, and a delete-to-empty has somewhere to
        // pop back to — the grid, exactly as in the app.
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PrivateImmersiveSession(
                      session: session,
                      systemUi: FakeImmersiveSystemUi(),
                    ),
                  ),
                ),
                child: const Text('grid'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('grid'));
  await tester.pumpAndSettle();
}

GallerySessionController<PrivateImage> _session(
  List<PrivateImage> images, {
  int initialIndex = 0,
}) {
  return GallerySessionController<PrivateImage>(
    identity: 'private-library',
    items: images,
    initialIndex: initialIndex,
    itemKey: (PrivateImage image) => image.id,
  );
}

Uri _location(String id) =>
    Uri.file('/data/user/0/cc.pym.tela/files/wallpapers/wallhaven-$id.jpg');

PrivateImage _image(String id, {int? width = 1080, int? height = 2400}) =>
    PrivateImage(
      id: id,
      location: _location(id),
      savedAt: DateTime.utc(2026, 7, 14),
      sizeBytes: 2048,
      width: width,
      height: height,
    );
