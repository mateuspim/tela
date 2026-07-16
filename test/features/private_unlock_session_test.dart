import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/features/private_library/private_immersive_session.dart';
import 'package:tela/features/private_library/private_library_screen.dart';

import '../fakes/fake_app_lock.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_immersive_system_ui.dart';
import '../fakes/fake_local_preview_cache.dart';
import '../fakes/fake_screen_guard.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_wallpaper_applier.dart';

/// The app-lock is a toll on entering the private tier, not on each screen of
/// it. These drive the real grid -> viewer route, because that pairing is where
/// the second prompt came from: both screens gate, and both used to charge.
void main() {
  testWidgets('a viewer opened over an unlocked grid inherits the unlock', (
    WidgetTester tester,
  ) async {
    final FakeAppLock lock = FakeAppLock();
    await _openLibrary(tester, lock: lock);
    expect(lock.prompts, 1, reason: 'the grid pays the toll');

    await _tapFirstTile(tester);

    expect(find.byType(PrivateImmersiveSession), findsOneWidget);
    expect(
      lock.prompts,
      1,
      reason: 'the viewer inherits it — one image, not two prompts',
    );
    // Inherited, not skipped: the gate still resolved, so content is shown
    // because the lock is satisfied and not because nobody asked.
    expect(find.byKey(const Key('private-viewer-set')), findsOneWidget);
  });

  testWidgets('a viewer reached cold still prompts', (
    WidgetTester tester,
  ) async {
    final FakeAppLock lock = FakeAppLock();
    // No grid unlock precedes this one: the viewer is the first private screen
    // reached, exactly as a deep link would reach it.
    await _openViewerAlone(tester, lock: lock);

    expect(lock.prompts, 1);
    expect(find.byKey(const Key('private-viewer-set')), findsOneWidget);
  });

  testWidgets('the unlock does not survive backgrounding', (
    WidgetTester tester,
  ) async {
    final FakeAppLock lock = FakeAppLock();
    await _openLibrary(tester, lock: lock);
    expect(lock.prompts, 1);

    await _background(tester);
    await _foreground(tester);
    await _tapFirstTile(tester);

    expect(
      lock.prompts,
      2,
      reason: 'the app left the foreground, so the toll is owed again',
    );
  });

  testWidgets('a refused prompt is never inherited', (
    WidgetTester tester,
  ) async {
    final FakeAppLock lock = FakeAppLock(passes: false);
    await _openLibrary(tester, lock: lock);
    expect(lock.prompts, 1);
    expect(find.text('The private library is locked.'), findsOneWidget);

    // The grid is still gated, so there is no tile to tap; a viewer reached
    // any other way must find nothing paid for it.
    await _openViewerAlone(tester, lock: lock);
    expect(lock.prompts, 2);
    expect(find.byKey(const Key('private-viewer-set')), findsNothing);
  });
}

Future<void> _tapFirstTile(WidgetTester tester) async {
  await tester.tap(find.byType(Image).first);
  await tester.pumpAndSettle();
}

/// Drives the app out of the foreground the way Android does, one legal step at
/// a time — `inactive` alone is not backgrounding, and the listener says so.
Future<void> _background(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
}

Future<void> _foreground(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
}

/// Mounts the private grid on a router that can reach the real viewer route.
Future<void> _openLibrary(WidgetTester tester, {required FakeAppLock lock}) {
  return _pumpRouter(tester, lock: lock, at: TelaRoutes.privateLibraryPath);
}

/// Mounts the viewer with no grid ever unlocked behind it.
Future<void> _openViewerAlone(
  WidgetTester tester, {
  required FakeAppLock lock,
}) {
  final GallerySessionController<PrivateImage> session =
      GallerySessionController<PrivateImage>(
        identity: 'private-library',
        items: <PrivateImage>[_image('e7jvjd')],
        initialIndex: 0,
        itemKey: (PrivateImage image) => image.id,
      );
  addTearDown(session.dispose);
  return _pumpRouter(
    tester,
    lock: lock,
    at: TelaRoutes.privateViewerPath,
    extra: session,
  );
}

Future<void> _pumpRouter(
  WidgetTester tester, {
  required FakeAppLock lock,
  required String at,
  Object? extra,
}) async {
  final FakeImageStore store = FakeImageStore(
    privateLibrary: <PrivateImage>[_image('e7jvjd')],
  );
  final GoRouter router = GoRouter(
    initialLocation: at,
    initialExtra: extra,
    routes: <RouteBase>[
      GoRoute(
        path: TelaRoutes.privateLibraryPath,
        name: TelaRoutes.privateLibraryName,
        builder: (_, _) => const PrivateLibraryScreen(),
      ),
      GoRoute(
        path: TelaRoutes.privateViewerPath,
        name: TelaRoutes.privateViewerName,
        builder: (BuildContext context, GoRouterState state) =>
            PrivateImmersiveSession(
              session: state.extra! as GallerySessionController<PrivateImage>,
              systemUi: FakeImmersiveSystemUi(),
            ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        imageStoreProvider.overrideWithValue(store),
        appLockProvider.overrideWithValue(lock),
        screenGuardProvider.overrideWithValue(FakeScreenGuard()),
        wallpaperApplierProvider.overrideWithValue(FakeWallpaperApplier()),
        localPreviewCacheProvider.overrideWithValue(FakeLocalPreviewCache()),
        settingsRepositoryProvider.overrideWithValue(
          FakeSettingsRepository(privateLibraryLocked: true),
        ),
      ],
      child: MaterialApp.router(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PrivateImage _image(String id) => PrivateImage(
  id: id,
  location: Uri.parse('file:///data/tela/$id.jpg'),
  savedAt: DateTime.utc(2026, 7, 14),
  sizeBytes: 2048,
  width: 1080,
  height: 2400,
);
