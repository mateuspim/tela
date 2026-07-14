import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/features/detail/wallpaper_detail_screen.dart';

import '../fakes/fake_download_history.dart';
import '../fakes/fake_favorites_repository.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_wallhaven_api.dart';

void main() {
  testWidgets('renders detail-only Wallhaven metadata after the preview', (
    WidgetTester tester,
  ) async {
    final WallpaperDetails details = _details();
    await _pumpDetail(tester, details);

    expect(find.text('Details'), findsOneWidget);
    expect(find.text('1,048,576 bytes'), findsOneWidget);
    expect(find.text('tela-fixture'), findsOneWidget);
    expect(find.text('landscape'), findsOneWidget);
    expect(find.text('sunset'), findsOneWidget);
  });

  testWidgets(
    'download button follows the saved settings without opening a sheet',
    (
      WidgetTester tester,
    ) async {
      final WallpaperDetails details = _details();
      final FakeImageStore imageStore = FakeImageStore();
      await _pumpDetail(
        tester,
        details,
        imageStore: imageStore,
        settings: StorageSettings.defaults.copyWith(
          sfwTier: StorageTier.filesOutsideGallery,
        ),
      );

      await tester.tap(find.bySemanticsLabel('Download'));
      await tester.pumpAndSettle();

      expect(imageStore.receivedImageUrl, details.wallpaper.fullImageUrl);
      expect(imageStore.receivedTier, StorageTier.filesOutsideGallery);
      expect(find.text('Wallpaper downloaded.'), findsOneWidget);
    },
  );

  testWidgets(
    'long-press download exposes all three one-download destinations',
    (WidgetTester tester) async {
      final WallpaperDetails details = _details();
      await _pumpDetail(tester, details);

      await tester.longPress(find.bySemanticsLabel('Download'));
      await tester.pumpAndSettle();

      expect(find.text('Download to'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Files, not gallery'), findsOneWidget);
      expect(find.text('Private library'), findsOneWidget);
    },
  );

  testWidgets('the gallery is not an option for an explicit wallpaper', (
    WidgetTester tester,
  ) async {
    final WallpaperDetails details = _details(purity: Purity.nsfw);
    await _pumpDetail(tester, details);

    await tester.longPress(find.bySemanticsLabel('Download'));
    await tester.pumpAndSettle();

    expect(find.text('Gallery'), findsNothing);
    expect(find.text('Files, not gallery'), findsOneWidget);
    expect(find.text('Private library'), findsOneWidget);
  });

  testWidgets('a download refreshes the listings that exist to show it', (
    WidgetTester tester,
  ) async {
    // Regression, found on hardware 2026-07-14. Both listings are plain (not
    // autoDispose) futures, so each resolves once per process and then caches.
    // Nothing dropped them when a download landed, so the file was written, the
    // row was inserted — and the download history and the private library went
    // on rendering the world as it looked when they were first opened. It read
    // as "the download didn't save"; only a relaunch showed it. Reading the
    // listing *before* the download is what reproduces it: that is the read
    // that used to poison the cache.
    final FakeDownloadHistory history = FakeDownloadHistory();
    final WallpaperDetails details = _details();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        wallhavenApiProvider.overrideWithValue(
          FakeWallhavenApi(details: details),
        ),
        secretStoreProvider.overrideWithValue(FakeSecretStore()),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        favoritesRepositoryProvider.overrideWithValue(
          FakeFavoritesRepository(),
        ),
        downloadHistoryProvider.overrideWithValue(history),
        imageStoreProvider.overrideWithValue(FakeImageStore()),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(recentDownloadsProvider.future), isEmpty);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: WallpaperDetailScreen(wallpaper: details.wallpaper),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Download'));
    await tester.pumpAndSettle();

    expect(history.recorded, hasLength(1));
    expect(await container.read(recentDownloadsProvider.future), hasLength(1));
  });
}

Future<void> _pumpDetail(
  WidgetTester tester,
  WallpaperDetails details, {
  FakeImageStore? imageStore,
  StorageSettings? settings,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallhavenApiProvider.overrideWithValue(
          FakeWallhavenApi(details: details),
        ),
        secretStoreProvider.overrideWithValue(FakeSecretStore()),
        settingsRepositoryProvider.overrideWithValue(
          FakeSettingsRepository(settings: settings),
        ),
        // The app bar now carries the favorites heart, so this screen reaches
        // the database. Left unbound, it opens the real one and leaks a timer.
        favoritesRepositoryProvider.overrideWithValue(
          FakeFavoritesRepository(),
        ),
        // Downloading records where the file landed — the same database again.
        downloadHistoryProvider.overrideWithValue(FakeDownloadHistory()),
        if (imageStore != null)
          imageStoreProvider.overrideWithValue(imageStore),
      ],
      child: MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: WallpaperDetailScreen(wallpaper: details.wallpaper),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

WallpaperDetails _details({Purity purity = Purity.sfw}) {
  final Wallpaper wallpaper = Wallpaper(
    id: 'e7jvjd',
    fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg',
    thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/e7jvjd.jpg',
    thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg',
    thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg',
    resolution: const Resolution(3840, 2160),
    fileSizeBytes: 1048576,
    purity: purity,
    category: Category.general,
    colors: const <String>['#660000'],
  );
  return WallpaperDetails(
    wallpaper: wallpaper,
    ratio: '1.78',
    fileType: 'image/jpeg',
    tags: const <WallpaperTag>[
      WallpaperTag(id: 101, name: 'landscape'),
      WallpaperTag(id: 202, name: 'sunset'),
    ],
    uploader: const WallpaperUploader(
      username: 'tela-fixture',
      group: 'User',
      avatarUrl: 'https://example.com/avatar.jpg',
    ),
    source: 'https://example.com/source',
    views: 4523,
    favorites: 128,
  );
}
