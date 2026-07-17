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
import 'package:tela/features/favorites/favorites_grid.dart';
import 'package:tela/features/library/library_screen.dart';

import '../fakes/fake_favorites_repository.dart';

void main() {
  testWidgets('the hub reaches history, the private library, and favorites', (
    WidgetTester tester,
  ) async {
    await _pumpLibrary(tester);

    // The two tiers that used to be buried in Settings sit above the shelf...
    expect(find.text('Download history'), findsOneWidget);
    expect(find.text('Private library'), findsOneWidget);
    // ...and the favorites shelf itself is embedded, empty here.
    expect(find.byType(FavoritesGrid), findsOneWidget);
    expect(find.textContaining('Nothing saved yet'), findsOneWidget);
  });

  testWidgets('the history entry opens the download history', (
    WidgetTester tester,
  ) async {
    await _pumpLibrary(tester);

    await tester.tap(find.text('Download history'));
    await tester.pumpAndSettle();

    expect(find.text('history-screen'), findsOneWidget);
  });

  testWidgets('the private entry opens the private library', (
    WidgetTester tester,
  ) async {
    await _pumpLibrary(tester);

    await tester.tap(find.text('Private library'));
    await tester.pumpAndSettle();

    expect(find.text('private-screen'), findsOneWidget);
  });
}

Future<void> _pumpLibrary(WidgetTester tester) async {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const LibraryScreen()),
      GoRoute(
        path: TelaRoutes.downloadHistoryPath,
        name: TelaRoutes.downloadHistoryName,
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('history-screen'))),
      ),
      GoRoute(
        path: TelaRoutes.privateLibraryPath,
        name: TelaRoutes.privateLibraryName,
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('private-screen'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        favoritesRepositoryProvider.overrideWithValue(
          FakeFavoritesRepository(),
        ),
      ],
      child: MaterialApp.router(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
