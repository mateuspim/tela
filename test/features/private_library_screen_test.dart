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

import '../fakes/fake_image_store.dart';
import '../fakes/fake_screen_guard.dart';

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

    testWidgets('long-press deletes only after it is confirmed', (
      WidgetTester tester,
    ) async {
      final FakeImageStore store = FakeImageStore(
        privateLibrary: <PrivateImage>[_image('e7jvjd')],
      );
      await _pump(tester, store);

      await tester.longPress(find.bySemanticsLabel('Private wallpaper e7jvjd'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(store.deletedIds, isEmpty, reason: 'a deletion is not undoable');

      await tester.longPress(find.bySemanticsLabel('Private wallpaper e7jvjd'));
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
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        imageStoreProvider.overrideWithValue(store),
        screenGuardProvider.overrideWithValue(guard ?? FakeScreenGuard()),
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
