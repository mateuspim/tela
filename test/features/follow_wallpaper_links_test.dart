import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/app.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/features/browse/browse_query_controller.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';

import '../fakes/fake_favorites_repository.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_wallhaven_api.dart';

/// A wallpaper is a place you can navigate *from* — this is that path, end to
/// end, through the real router: browse, a wallpaper, and out along one of the
/// two links its detail screen prints.
void main() {
  testWidgets('a tag chip opens that tag, and Back returns to the wallpaper', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = _api();
    await _pumpDetail(tester, api);

    await _follow(tester, find.text('nature'));

    expect(find.text('Wallpapers with this tag'), findsOneWidget);
    expect(api.receivedQueries.last.term, 'id:37');

    await tester.pageBack();
    await _finishTransition(tester);

    expect(find.text('Set wallpaper'), findsOneWidget);
  });

  testWidgets('the uploader opens their uploads', (WidgetTester tester) async {
    final FakeWallhavenApi api = _api();
    await _pumpDetail(tester, api);

    await _follow(tester, find.text('pym'));

    expect(find.text('Uploads by this user'), findsOneWidget);
    expect(api.receivedQueries.last.term, '@pym');
  });

  testWidgets('the browse tabs are left as they were', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = _api();
    final ProviderContainer container = await _pumpDetail(tester, api);

    await _follow(tester, find.text('nature'));
    await tester.pageBack();
    await _finishTransition(tester);
    await tester.pageBack();
    await _finishTransition(tester);

    // A listing is pushed, never applied to the tabs underneath: the browse
    // grid the user came back to is still browsing, not searching for a tag.
    expect(find.byType(WallpaperTile), findsWidgets);
    expect(container.read(browseQueryProvider).term, isEmpty);
  });
}

/// Boots the whole app and taps through to one wallpaper's detail screen.
Future<ProviderContainer> _pumpDetail(
  WidgetTester tester,
  FakeWallhavenApi api,
) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      wallhavenApiProvider.overrideWithValue(api),
      secretStoreProvider.overrideWithValue(FakeSecretStore()),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      favoritesRepositoryProvider.overrideWithValue(FakeFavoritesRepository()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const TelaApp(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  await tester.tap(find.byType(WallpaperTile).first);
  await _finishTransition(tester);
  return container;
}

/// Scrolls the metadata panel into view and follows the link in it.
///
/// The links live under the preview, which fills half the screen — on a
/// phone-sized test viewport they are below the fold, where nothing can be
/// tapped.
Future<void> _follow(WidgetTester tester, Finder link) async {
  await tester.ensureVisible(link);
  await tester.pump();
  await tester.tap(link);
  await _finishTransition(tester);
}

Future<void> _finishTransition(WidgetTester tester) async {
  // The full-resolution network image intentionally keeps a progress indicator
  // alive in widget tests, so pumpAndSettle can never reach quiescence.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

FakeWallhavenApi _api() => FakeWallhavenApi(
  page: const WallpaperPage(
    wallpapers: <Wallpaper>[_wallpaper],
    currentPage: 1,
    lastPage: 1,
  ),
  details: const WallpaperDetails(
    wallpaper: _wallpaper,
    ratio: '0.45',
    fileType: 'image/jpeg',
    tags: <WallpaperTag>[WallpaperTag(id: 37, name: 'nature')],
    uploader: WallpaperUploader(
      username: 'pym',
      group: 'User',
      avatarUrl: 'https://wallhaven.cc/avatar/pym.jpg',
    ),
    source: '',
    views: 12,
    favorites: 3,
  ),
);

const Wallpaper _wallpaper = Wallpaper(
  id: 'e7jvjd',
  fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/e7jvjd.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg',
  resolution: Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: Purity.sfw,
  category: Category.general,
  colors: <String>[],
);
