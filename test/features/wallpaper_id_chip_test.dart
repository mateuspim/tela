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
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/features/browse/browse_screen.dart';
import 'package:tela/features/browse/wallpaper_id_chip.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallpaper_source.dart';

/// Typing a wallpaper id into the browse search box offers to open it.
///
/// The rule the whole feature hangs on: this is an *offer beside* the search,
/// never an interception of it. The Enter-still-searches test below is the one
/// that must never be deleted — the design was chosen over a jump-on-submit
/// precisely because a real six-character search term must not be hijacked.
void main() {
  group('WallpaperIdChip — when it is offered', () {
    testWidgets('stays hidden for an ordinary search term', (
      WidgetTester tester,
    ) async {
      await _pumpBrowse(tester, _source());

      await _type(tester, 'sunset');

      expect(_chip, findsNothing);
    });

    testWidgets('appears once the text has the active source id shape', (
      WidgetTester tester,
    ) async {
      await _pumpBrowse(tester, _source());

      await _type(tester, 'je9ldp');

      expect(find.text('Go to wallpaper je9ldp'), findsOneWidget);
    });

    testWidgets('offers the normalized id an auto-capital produced', (
      WidgetTester tester,
    ) async {
      // A phone keyboard capitalizes the first letter, which is where the
      // owner's own "Je9ldp" came from. The chip must show — and later ask
      // for — the lowercase id the API will actually answer.
      await _pumpBrowse(tester, _source());

      await _type(tester, 'Je9ldp');

      expect(find.text('Go to wallpaper je9ldp'), findsOneWidget);
    });

    testWidgets('never appears for a source that recognizes no ids', (
      WidgetTester tester,
    ) async {
      // The default fake recognizes nothing, standing in for a source with no
      // id shape to offer.
      await _pumpBrowse(tester, FakeWallpaperSource(page: _page));

      await _type(tester, 'je9ldp');

      expect(_chip, findsNothing);
    });

    testWidgets('moves neither the tabs nor the grid when it appears', (
      WidgetTester tester,
    ) async {
      // The device complaint this layout exists to answer: the chip used to
      // sit in the app bar and shove the whole tab row down mid-typing. It
      // floats over the listing now, so nothing below it may shift by a pixel.
      await _pumpBrowse(tester, _source());
      final Offset tabs = tester.getTopLeft(find.byType(TabBar));
      final Offset grid = tester.getTopLeft(find.byType(TabBarView));

      await _type(tester, 'je9ldp');

      expect(_chip, findsOneWidget);
      expect(tester.getTopLeft(find.byType(TabBar)), tabs);
      expect(tester.getTopLeft(find.byType(TabBarView)), grid);
    });

    testWidgets('drops to an icon on a phone-width field', (
      WidgetTester tester,
    ) async {
      // The tablet's field is ~1400px and swallows the whole sentence; a phone
      // in portrait has no such room, and the action must survive the squeeze
      // rather than disappear below some width.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpBrowse(tester, _source());

      await _type(tester, 'je9ldp');

      expect(_chip, findsNothing);
      expect(find.byTooltip('Go to wallpaper je9ldp'), findsOneWidget);
    });

    testWidgets('goes away when the field is cleared', (
      WidgetTester tester,
    ) async {
      await _pumpBrowse(tester, _source());
      await _type(tester, 'je9ldp');
      expect(_chip, findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(_chip, findsNothing);
    });
  });

  group('WallpaperIdChip — what it does not do', () {
    testWidgets('Enter still runs an ordinary text search on an id', (
      WidgetTester tester,
    ) async {
      // The whole reason this is a chip and not a submit-time jump. Deleting
      // this test would let a search hijack back in unnoticed.
      final FakeWallpaperSource source = _source();
      await _pumpBrowse(tester, source);

      await tester.enterText(find.byType(TextField), 'je9ldp');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        source.receivedQueries.map((SearchQuery q) => q.term),
        contains('je9ldp'),
      );
      expect(source.receivedDetailIds, isEmpty);
      expect(find.byType(BrowseScreen), findsOneWidget);
    });
  });

  group('WallpaperIdChip — the jump', () {
    testWidgets('opens the wallpaper the id names', (
      WidgetTester tester,
    ) async {
      final FakeWallpaperSource source = _source(
        details: _detailsFor('je9ldp'),
      );
      await _pumpBrowse(tester, source);
      await _type(tester, 'je9ldp');

      await tester.tap(_chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(source.receivedDetailIds, <String>['je9ldp']);
      expect(find.text('detail:je9ldp'), findsOneWidget);
    });

    testWidgets('asks for the lowercase id after an auto-capital', (
      WidgetTester tester,
    ) async {
      // The regression guard for the 404 that "Je9ldp" would otherwise cause.
      final FakeWallpaperSource source = _source(
        details: _detailsFor('je9ldp'),
      );
      await _pumpBrowse(tester, source);
      await _type(tester, 'Je9ldp');

      await tester.tap(_chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(source.receivedDetailIds, <String>['je9ldp']);
    });

    testWidgets('says so and stays put when no wallpaper has that id', (
      WidgetTester tester,
    ) async {
      final FakeWallpaperSource source = _source(
        detailFailure: NotFoundFailure('je9ldq'),
      );
      await _pumpBrowse(tester, source);
      await _type(tester, 'je9ldq');

      await tester.tap(_chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('No wallpaper je9ldq on Wallhaven.'), findsOneWidget);
      expect(find.byType(BrowseScreen), findsOneWidget);
      expect(find.textContaining('detail:'), findsNothing);
    });

    testWidgets('reports a network miss without navigating', (
      WidgetTester tester,
    ) async {
      final FakeWallpaperSource source = _source(
        detailFailure: const NetworkFailure(),
      );
      await _pumpBrowse(tester, source);
      await _type(tester, 'je9ldp');

      await tester.tap(_chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('detail:'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}

/// The chip as a person sees it.
///
/// Not `find.byType(WallpaperIdChip)`: the widget stays mounted and shrinks to
/// nothing when there is no id, so that the grid under it is never relaid out.
/// Mounted is not showing, and only showing is what these tests mean.
final Finder _chip = find.descendant(
  of: find.byType(WallpaperIdChip),
  matching: find.byType(ActionChip),
);

/// Wallhaven's real id shape, so the chip is exercised against the alphabet
/// the live API was measured to use rather than a looser stand-in.
final RegExp _wallhavenIdShape = RegExp(r'^[0-9degjklmnopqrvwxyz]{6}$');

String? _wallhavenIdIn(String text) {
  final String candidate = text.trim().toLowerCase();
  return _wallhavenIdShape.hasMatch(candidate) ? candidate : null;
}

FakeWallpaperSource _source({
  WallpaperDetails? details,
  SourceFailure? detailFailure,
}) {
  return FakeWallpaperSource(
    page: _page,
    details: details,
    detailFailure: detailFailure,
    idIn: _wallhavenIdIn,
  );
}

const WallpaperPage _page = WallpaperPage(
  wallpapers: <Wallpaper>[],
  hasMore: false,
  currentPage: 1,
  lastPage: 1,
);

/// Types [text] without submitting — the chip rides `onChanged`, not Enter.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

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

WallpaperDetails _detailsFor(String id) => WallpaperDetails(
  wallpaper: _wallpaper(id),
  fileType: 'image/jpeg',
  ratio: '0.45',
  views: 10,
  favorites: 2,
  tags: const <WallpaperTag>[],
  uploader: const WallpaperUploader(
    username: 'tela-fixture',
    group: '',
    avatarUrl: '',
  ),
  source: '',
);

/// Boots the real BrowseScreen under a router, because the jump is a route
/// push and a `MaterialApp` without one cannot see it happen.
Future<void> _pumpBrowse(
  WidgetTester tester,
  FakeWallpaperSource source,
) async {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const BrowseScreen()),
      GoRoute(
        path: TelaRoutes.detailPath,
        name: TelaRoutes.detailName,
        builder: (_, GoRouterState state) {
          // Faithful to the real router's bare-Wallpaper branch, which is the
          // shape an id jump pushes.
          final Wallpaper wallpaper = state.extra! as Wallpaper;
          return Scaffold(body: Text('detail:${wallpaper.id}'));
        },
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallhavenSourceProvider.overrideWithValue(source),
        secretStoreProvider.overrideWithValue(FakeSecretStore()),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        tagBlocklistRepositoryProvider.overrideWithValue(
          FakeTagBlocklistRepository(),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  // Not pumpAndSettle: the tiles' fade-in never reaches a quiescent frame in a
  // test binding.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
