import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/features/detail/wallpaper_detail_screen.dart';
import 'package:tela/features/favorites/favorite_button.dart';

import '../fakes/fake_download_history.dart';
import '../fakes/fake_favorites_repository.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_immersive_system_ui.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallhaven_api.dart';
import '../fakes/fake_wallpaper_applier.dart';
import '../fakes/fake_wallpaper_sharer.dart';

void main() {
  testWidgets(
    'uses an uncropped thumbnail in the same frame as the full image',
    (WidgetTester tester) async {
      final WallpaperDetails details = _details();
      await _pumpDetail(tester, details);

      final List<CachedNetworkImage> layers = tester
          .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .where(
            (CachedNetworkImage image) =>
                image.imageUrl == details.wallpaper.thumbOriginalUrl ||
                image.imageUrl == details.wallpaper.fullImageUrl,
          )
          .toList();

      expect(
        layers.map((CachedNetworkImage image) => image.imageUrl),
        <String>[
          details.wallpaper.thumbOriginalUrl,
          details.wallpaper.fullImageUrl,
        ],
      );
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is CachedNetworkImage &&
              widget.imageUrl == details.wallpaper.thumbLargeUrl,
        ),
        findsNothing,
      );
      final Finder previewLayer = find.byWidget(layers.first);
      final Finder fullLayer = find.byWidget(layers.last);
      expect(tester.getSize(previewLayer), tester.getSize(fullLayer));
    },
  );

  testWidgets('offers an immersive preview and a clear 48dp close control', (
    WidgetTester tester,
  ) async {
    final FakeImmersiveSystemUi systemUi = FakeImmersiveSystemUi();
    await _pumpDetail(tester, _details(), immersiveSystemUi: systemUi);

    await tester.tap(find.byTooltip('View wallpaper full screen'));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Set wallpaper'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
    final Size closeTarget = tester.getSize(
      find.byKey(const Key('immersive-viewer-close')),
    );
    expect(closeTarget.width, greaterThanOrEqualTo(48));
    expect(closeTarget.height, greaterThanOrEqualTo(48));
    expect(systemUi.enterCalls, 1);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Set wallpaper'), findsOneWidget);
    expect(systemUi.restoreCalls, 1);
  });

  testWidgets('Back exits fullscreen before leaving Detail', (
    WidgetTester tester,
  ) async {
    final FakeImmersiveSystemUi systemUi = FakeImmersiveSystemUi();
    await _pumpDetail(tester, _details(), immersiveSystemUi: systemUi);

    await tester.tap(find.byTooltip('View wallpaper full screen'));
    await tester.pumpAndSettle();
    expect(find.text('Set wallpaper'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Set wallpaper'), findsOneWidget);
    expect(find.byType(WallpaperDetailScreen), findsOneWidget);
    expect(systemUi.restoreCalls, 1);
  });

  testWidgets(
    'gallery navigation resets zoom and rebinds Detail and its actions',
    (WidgetTester tester) async {
      final WallpaperDetails first = _details();
      final WallpaperDetails second = _otherDetails();
      final GallerySessionController<Wallpaper> gallery =
          GallerySessionController<Wallpaper>(
            identity: 'favorites',
            items: <Wallpaper>[first.wallpaper, second.wallpaper],
            initialIndex: 0,
          );
      final FakeWallhavenApi api = FakeWallhavenApi(
        detailsById: <String, WallpaperDetails>{
          first.wallpaper.id: first,
          second.wallpaper.id: second,
        },
      );
      final FakeImageStore imageStore = FakeImageStore();
      final FakeWallpaperSharer sharer = FakeWallpaperSharer();
      final FakeWallpaperApplier applier = FakeWallpaperApplier();
      await _pumpDetail(
        tester,
        first,
        api: api,
        gallerySession: gallery,
        imageStore: imageStore,
        sharer: sharer,
        applier: applier,
        disableAnimations: true,
      );

      await tester.tap(find.byTooltip('View wallpaper full screen'));
      await tester.pumpAndSettle();
      tester
          .widget<ButtonStyleButton>(
            find.byKey(const Key('immersive-viewer-zoom')),
          )
          .onPressed!();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Reset zoom'), findsOneWidget);

      tester
          .widget<ButtonStyleButton>(
            find.byKey(const Key('immersive-viewer-next')),
          )
          .onPressed!();
      await tester.pump();

      expect(gallery.selectedItem, second.wallpaper);
      expect(find.text('Zoom in'), findsOneWidget);
      expect(find.bySemanticsLabel('2 of 2'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Wallpaper ${second.wallpaper.id}'),
        findsOneWidget,
      );

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      final FavoriteButton favorite = tester.widget<FavoriteButton>(
        find.byType(FavoriteButton),
      );
      expect(favorite.wallpaper, second.wallpaper);
      expect(find.text('second-uploader'), findsOneWidget);

      await tester.tap(find.text('Set wallpaper'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home screen'));
      await tester.pumpAndSettle();
      expect(applier.receivedSource, Uri.parse(second.wallpaper.fullImageUrl));

      await tester.tap(find.bySemanticsLabel('Download'));
      await tester.pumpAndSettle();
      expect(imageStore.receivedImageUrl, second.wallpaper.fullImageUrl);

      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();
      expect(
        sharer.sharedLinks.single,
        Uri.parse('https://wallhaven.cc/w/${second.wallpaper.id}'),
      );

      await tester.pumpWidget(const SizedBox());
      gallery.dispose();
    },
  );

  testWidgets('uses preview and information panes on a wide screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDetail(tester, _details());

    final Offset preview = tester.getTopLeft(
      find.byKey(const Key('detail-preview-pane')),
    );
    final Offset information = tester.getTopLeft(
      find.byKey(const Key('detail-information-pane')),
    );
    expect(preview.dx, lessThan(information.dx));
  });

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

  testWidgets('long-pressing a tag asks before blocking it', (
    WidgetTester tester,
  ) async {
    final WallpaperDetails details = _details();
    await _pumpDetail(tester, details);

    await tester.ensureVisible(find.text('landscape'));
    await tester.pump();
    await tester.longPress(find.text('landscape'));
    await tester.pumpAndSettle();

    expect(find.text('Block this tag?'), findsOneWidget);
    expect(
      find.text(
        'You won\'t see wallpapers tagged "landscape" in search results '
        'anymore. Unblock it any time from Settings.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('confirming the dialog blocks the tag and says so', (
    WidgetTester tester,
  ) async {
    final WallpaperDetails details = _details();
    final FakeTagBlocklistRepository blocklist = FakeTagBlocklistRepository();
    await _pumpDetail(tester, details, blocklist: blocklist);

    await tester.ensureVisible(find.text('landscape'));
    await tester.pump();
    await tester.longPress(find.text('landscape'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();

    expect(blocklist.blockedIds(), <int>{101});
    expect(
      find.text(
        'Blocked "landscape". You won\'t see it in search results anymore.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('cancelling the dialog leaves the tag unblocked', (
    WidgetTester tester,
  ) async {
    final WallpaperDetails details = _details();
    final FakeTagBlocklistRepository blocklist = FakeTagBlocklistRepository();
    await _pumpDetail(tester, details, blocklist: blocklist);

    await tester.ensureVisible(find.text('landscape'));
    await tester.pump();
    await tester.longPress(find.text('landscape'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(blocklist.blockedIds(), isEmpty);
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

  testWidgets('the share menu offers the link and the image for safe content', (
    WidgetTester tester,
  ) async {
    final WallpaperDetails details = _details();
    await _pumpDetail(tester, details);

    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();

    expect(find.text('Share wallpaper'), findsOneWidget);
    expect(find.text('Link'), findsOneWidget);
    expect(find.text('Image'), findsOneWidget);
  });

  testWidgets('the share menu withholds the image for an explicit wallpaper', (
    WidgetTester tester,
  ) async {
    // The NSFW invariant reaches the share sheet too: an explicit image file
    // may never leave the device, so only the public link is offered.
    final WallpaperDetails details = _details(purity: Purity.nsfw);
    await _pumpDetail(tester, details);

    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();

    expect(find.text('Link'), findsOneWidget);
    expect(find.text('Image'), findsNothing);
  });

  testWidgets('sharing the link routes the wallpaper to the sharer port', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSharer sharer = FakeWallpaperSharer();
    final WallpaperDetails details = _details();
    await _pumpDetail(tester, details, sharer: sharer);

    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();

    expect(sharer.sharedLinks, <Uri>[
      Uri.parse('https://wallhaven.cc/w/${details.wallpaper.id}'),
    ]);
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
        tagBlocklistRepositoryProvider.overrideWithValue(
          FakeTagBlocklistRepository(),
        ),
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
  FakeWallpaperSharer? sharer,
  FakeTagBlocklistRepository? blocklist,
  FakeImmersiveSystemUi? immersiveSystemUi,
  FakeWallhavenApi? api,
  GallerySessionController<Wallpaper>? gallerySession,
  FakeWallpaperApplier? applier,
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallhavenApiProvider.overrideWithValue(
          api ?? FakeWallhavenApi(details: details),
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
        // The share button would otherwise reach the real method channel.
        wallpaperSharerProvider.overrideWithValue(
          sharer ?? FakeWallpaperSharer(),
        ),
        // Blocking a tag reaches the database too.
        tagBlocklistRepositoryProvider.overrideWithValue(
          blocklist ?? FakeTagBlocklistRepository(),
        ),
        if (imageStore != null)
          imageStoreProvider.overrideWithValue(imageStore),
        if (applier != null)
          wallpaperApplierProvider.overrideWithValue(applier),
      ],
      child: MaterialApp(
        builder: disableAnimations
            ? (BuildContext context, Widget? child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: true),
                child: child!,
              )
            : null,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: WallpaperDetailScreen(
          wallpaper: gallerySession == null ? details.wallpaper : null,
          gallerySession: gallerySession,
          immersiveSystemUi: immersiveSystemUi ?? FakeImmersiveSystemUi(),
        ),
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

WallpaperDetails _otherDetails() {
  const Wallpaper wallpaper = Wallpaper(
    id: 'bbb222',
    fullImageUrl: 'https://w.wallhaven.cc/full/bb/wallhaven-bbb222.jpg',
    thumbSmallUrl: 'https://th.wallhaven.cc/small/bb/bbb222.jpg',
    thumbLargeUrl: 'https://th.wallhaven.cc/lg/bb/bbb222.jpg',
    thumbOriginalUrl: 'https://th.wallhaven.cc/orig/bb/bbb222.jpg',
    resolution: Resolution(2160, 3840),
    fileSizeBytes: 2048,
    purity: Purity.sfw,
    category: Category.general,
    colors: <String>['#0066cc'],
  );
  return const WallpaperDetails(
    wallpaper: wallpaper,
    ratio: '0.56',
    fileType: 'image/jpeg',
    tags: <WallpaperTag>[WallpaperTag(id: 303, name: 'portrait')],
    uploader: WallpaperUploader(
      username: 'second-uploader',
      group: 'User',
      avatarUrl: 'https://example.com/second-avatar.jpg',
    ),
    source: '',
    views: 12,
    favorites: 3,
  );
}
