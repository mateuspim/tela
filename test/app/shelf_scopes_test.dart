import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/app.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/ui/wallpaper_marks_scope.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';

import '../fakes/fake_download_history.dart';
import '../fakes/fake_download_queue.dart';
import '../fakes/fake_favorites_repository.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallpaper_source.dart';

/// Where the tile marks are watched, and why it is below the app and not above.
///
/// Building `MaterialApp` reconstructs both `ThemeData`s from scratch. The
/// marks change every time a download lands — three a second through a
/// draining batch — so watching them in `TelaApp.build` rebuilt the whole app
/// and both themes at that rate. That is the background half of "the
/// application seems to be sluggish when downloading images on the background"
/// (the owner, 2026-08-24).
void main() {
  testWidgets('a landed download does not rebuild the app or its themes', (
    WidgetTester tester,
  ) async {
    final FakeDownloadHistory history = FakeDownloadHistory();
    final ProviderContainer container = await _pumpApp(tester, history);
    final MaterialApp before = tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );

    await _download(container, history);
    await tester.pump();

    // The very same widget instance: `TelaApp.build` did not run, so neither
    // `TelaTheme.light` nor `TelaTheme.dark` was called again. Move the marks
    // back into that method and this is what goes red.
    expect(
      identical(tester.widget<MaterialApp>(find.byType(MaterialApp)), before),
      isTrue,
      reason: 'a mark must not cost a theme rebuild',
    );
  });

  testWidgets('but the mark itself still arrives', (
    WidgetTester tester,
  ) async {
    // The other half, and the reason the test above is not just "nothing
    // happens". Moving the watch below the app must not stop the wall
    // learning that a wallpaper is now downloaded.
    final FakeDownloadHistory history = FakeDownloadHistory();
    final ProviderContainer container = await _pumpApp(tester, history);
    expect(_marks(tester).downloaded, isEmpty);

    await _download(container, history);
    await tester.pump();

    expect(_marks(tester).downloaded, <String>{'wallhaven-e7jvjd'});
  });
}

/// The scope every shelf reads its marks from.
WallpaperMarksScope _marks(WidgetTester tester) =>
    tester.widget<WallpaperMarksScope>(find.byType(WallpaperMarksScope));

/// Records a download and lets the listings catch up.
Future<void> _download(
  ProviderContainer container,
  FakeDownloadHistory history,
) async {
  await history.record(
    wallpaper: _wallpaper(),
    tier: StorageTier.sharedGallery,
    location: Uri.parse('memory://e7jvjd'),
  );
  container.invalidate(recentDownloadsProvider);
  await container.read(downloadedKeysProvider.future);
}

Future<ProviderContainer> _pumpApp(
  WidgetTester tester,
  FakeDownloadHistory history,
) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      wallhavenSourceProvider.overrideWithValue(FakeWallpaperSource()),
      secretStoreProvider.overrideWithValue(FakeSecretStore()),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      favoritesRepositoryProvider.overrideWithValue(FakeFavoritesRepository()),
      tagBlocklistRepositoryProvider.overrideWithValue(
        FakeTagBlocklistRepository(),
      ),
      downloadQueueProvider.overrideWithValue(FakeDownloadQueue()),
      downloadHistoryProvider.overrideWithValue(history),
      imageStoreProvider.overrideWithValue(FakeImageStore()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const TelaApp()),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
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
