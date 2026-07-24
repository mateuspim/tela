import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/app.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallhaven_api.dart';
import '../fakes/fake_wallpaper_applier.dart';

void main() {
  testWidgets('grid to preview to both screens is a three-tap core loop', (
    WidgetTester tester,
  ) async {
    final Wallpaper wallpaper = _wallpaper();
    final FakeWallhavenApi api = FakeWallhavenApi(
      page: WallpaperPage(
        wallpapers: <Wallpaper>[wallpaper],
        hasMore: false,
        currentPage: 1,
        lastPage: 1,
      ),
    );
    final FakeWallpaperApplier applier = FakeWallpaperApplier();
    await _pumpApp(tester, api, applier);

    await tester.tap(find.byType(WallpaperTile).first);
    await _finishTransition(tester);
    expect(find.text('Set wallpaper'), findsOneWidget);

    await tester.tap(find.text('Set wallpaper'));
    await _finishTransition(tester);
    expect(find.text('Set wallpaper on'), findsOneWidget);

    await tester.tap(find.text('Home and lock screens'));
    await _finishTransition(tester);

    expect(applier.callCount, 1);
    expect(applier.receivedSource, Uri.parse(wallpaper.fullImageUrl));
    expect(applier.receivedTarget, WallpaperTarget.both);
    expect(find.text('Wallpaper set.'), findsOneWidget);
  });
}

Future<void> _pumpApp(
  WidgetTester tester,
  FakeWallhavenApi api,
  FakeWallpaperApplier applier,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallhavenApiProvider.overrideWithValue(api),
        secretStoreProvider.overrideWithValue(FakeSecretStore()),
        wallpaperApplierProvider.overrideWithValue(applier),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        tagBlocklistRepositoryProvider.overrideWithValue(
          FakeTagBlocklistRepository(),
        ),
      ],
      child: const TelaApp(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _finishTransition(WidgetTester tester) async {
  // The full-resolution network image intentionally keeps a progress indicator
  // alive in widget tests, so pumpAndSettle can never reach quiescence.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Wallpaper _wallpaper() => Wallpaper(
  id: 'e7jvjd',
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/e7jvjd'),
  fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/e7jvjd.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg',
  resolution: const Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);
