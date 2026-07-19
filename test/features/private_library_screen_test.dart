import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/features/private_library/private_library_screen.dart';

import '../fakes/fake_app_lock.dart';
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

      expect(store.deletedIds, isEmpty, reason: 'a deletion is not undoable');
      // The cancelled dialog leaves the tick alone: the user cancelled the
      // deletion, not the selection.
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(store.deletedIds, <String>['e7jvjd']);
      expect(find.textContaining('Nothing here'), findsOneWidget);
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
}

Future<void> _pump(
  WidgetTester tester,
  FakeImageStore store, {
  FakeScreenGuard? guard,
  FakeAppLock? lock,
  bool locked = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        imageStoreProvider.overrideWithValue(store),
        screenGuardProvider.overrideWithValue(guard ?? FakeScreenGuard()),
        appLockProvider.overrideWithValue(lock ?? FakeAppLock()),
        settingsRepositoryProvider.overrideWithValue(
          FakeSettingsRepository(privateLibraryLocked: locked),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: PrivateLibraryScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PrivateImage _image(String id) => PrivateImage(
  id: id,
  location: Uri.file('/data/user/0/cc.pym.tela/files/wallpapers/w-$id.jpg'),
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
