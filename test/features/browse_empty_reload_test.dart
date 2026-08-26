import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/features/browse/wallpaper_grid.dart';

import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallpaper_source.dart';

/// A wall that answered with nothing is not a dead end.
///
/// The owner's report (2026-08-25): *"if the page im at like the latest doesnt
/// show images we need to show a button reload again"*. The retry button
/// already existed — but only on the branch where the fetch *failed*. A fetch
/// that succeeded with zero items drew a sentence and no button, and on Latest
/// that sentence also blamed filters that were not set.
///
/// Pull-to-refresh worked here the whole time, which is exactly why this is
/// worth a test: the capability was never missing, so nothing failing could
/// have told anyone the affordance was.
void main() {
  testWidgets('an empty listing offers a reload, and it refetches', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = FakeWallpaperSource(page: _empty);

    await _pumpGrid(tester, source, const SearchQuery());
    await tester.pump(const Duration(milliseconds: 300));

    expect(source.receivedQueries, hasLength(1));
    final Finder reload = find.widgetWithText(FilledButton, 'Reload');
    expect(reload, findsOneWidget, reason: 'a blank wall must offer a way out');

    await tester.tap(reload);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      source.receivedQueries,
      hasLength(2),
      reason: 'the button has to actually ask the source again',
    );
  });

  testWidgets('an unfiltered listing does not blame filters it does not have', (
    WidgetTester tester,
  ) async {
    // Latest, empty. "No wallpapers match these filters" would send the user
    // to clear filters that are not set — the wrong instruction, confidently
    // given.
    await _pumpGrid(
      tester,
      FakeWallpaperSource(page: _empty),
      const SearchQuery(),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('This listing came back with no wallpapers.'), findsOne);
    expect(find.text('No wallpapers match these filters.'), findsNothing);
  });

  testWidgets('a search that found nothing still says so', (
    WidgetTester tester,
  ) async {
    // The other half: here the filters really are the reason, and the original
    // sentence is the right one. Both offer the same reload.
    await _pumpGrid(
      tester,
      FakeWallpaperSource(page: _empty),
      const SearchQuery(term: 'zxcvbn'),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No wallpapers match these filters.'), findsOne);
    expect(find.widgetWithText(FilledButton, 'Reload'), findsOneWidget);
  });
}

/// A listing that answered, and answered with nothing — the state under test.
/// `hasMore: false`, so the grid does not chase a second page and mask it.
const WallpaperPage _empty = WallpaperPage(
  wallpapers: <Wallpaper>[],
  hasMore: false,
  currentPage: 1,
  lastPage: 1,
);

Future<void> _pumpGrid(
  WidgetTester tester,
  FakeWallpaperSource source,
  SearchQuery query,
) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallhavenSourceProvider.overrideWithValue(source),
        // Mounting the grid reads the standing blocklist. Left unbound, it
        // opens the real database.
        tagBlocklistRepositoryProvider.overrideWithValue(
          FakeTagBlocklistRepository(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: WallpaperGrid(query: query),
      ),
    ),
  );
}
