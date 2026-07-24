import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/blurred_image_backdrop.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/gallery_viewport.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_destination_streak.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/external_link_failure.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/features/detail/wallpaper_detail_screen.dart';
import 'package:tela/features/favorites/favorite_button.dart';

import '../fakes/fake_download_history.dart';
import '../fakes/fake_external_link.dart';
import '../fakes/fake_favorites_repository.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_immersive_system_ui.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_system_wallpaper_editor.dart';
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

      // Scoped to the contained frame: the letterbox backdrop behind it is a
      // third layer on the same thumbnail, and it is not one of these two.
      final List<CachedNetworkImage> layers = tester
          .widgetList<CachedNetworkImage>(
            find.descendant(
              of: find.byKey(GalleryViewport.imageFrameKey),
              matching: find.byType(CachedNetworkImage),
            ),
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

  testWidgets('the fullscreen viewer can favorite, download and set', (
    WidgetTester tester,
  ) async {
    // It was the only viewer in the app with no actions at all: you looked at
    // a wallpaper full-bleed, decided you wanted it, and had to close out to
    // Detail to say so (owner, 2026-07-19).
    await _pumpDetail(tester, _details());

    await tester.tap(find.byTooltip('View wallpaper full screen'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('immersive-viewer-favorite')), findsOneWidget);
    expect(find.byKey(const Key('immersive-viewer-download')), findsOneWidget);
    expect(find.byKey(const Key('immersive-viewer-set')), findsOneWidget);
  });

  testWidgets('favoriting from the fullscreen viewer saves and re-marks', (
    WidgetTester tester,
  ) async {
    final FakeFavoritesRepository favorites = FakeFavoritesRepository();
    await _pumpDetail(tester, _details(), favorites: favorites);

    await tester.tap(find.byTooltip('View wallpaper full screen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('immersive-viewer-favorite')));
    await tester.pumpAndSettle();

    expect(
      await favorites.isFavorite(
        const WallpaperRef(SourceId.wallhaven, 'e7jvjd'),
      ),
      isTrue,
    );
    // And the heart fills without leaving the viewer, which is the half a
    // repository assertion cannot show.
    expect(find.bySemanticsLabel('Remove from favorites'), findsOneWidget);
  });

  testWidgets('downloading from the fullscreen viewer stores the wallpaper', (
    WidgetTester tester,
  ) async {
    final FakeImageStore images = FakeImageStore();
    await _pumpDetail(tester, _details(), imageStore: images);

    await tester.tap(find.byTooltip('View wallpaper full screen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('immersive-viewer-download')));
    await tester.pumpAndSettle();

    expect(images.receivedId, 'e7jvjd');
  });

  testWidgets('offers an immersive preview and a clear 48dp close control', (
    WidgetTester tester,
  ) async {
    final FakeImmersiveSystemUi systemUi = FakeImmersiveSystemUi();
    await _pumpDetail(tester, _details(), immersiveSystemUi: systemUi);

    await tester.tap(find.byTooltip('View wallpaper full screen'));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Set wallpaper'), findsNothing);
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    final Size closeTarget = tester.getSize(
      find.byKey(const Key('immersive-viewer-close')),
    );
    expect(closeTarget.width, greaterThanOrEqualTo(48));
    expect(closeTarget.height, greaterThanOrEqualTo(48));
    expect(systemUi.enterCalls, 1);

    await tester.tap(find.byKey(const Key('immersive-viewer-close')));
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
          .widget<IconButton>(
            find.byKey(const Key('immersive-viewer-zoom')),
          )
          .onPressed!();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.bySemanticsLabel('Reset zoom'), findsOneWidget);

      tester
          .widget<IconButton>(
            find.byKey(const Key('immersive-viewer-next')),
          )
          .onPressed!();
      await tester.pump();

      expect(gallery.selectedItem, second.wallpaper);
      expect(find.bySemanticsLabel('Zoom in'), findsOneWidget);
      expect(find.bySemanticsLabel('2 of 2'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Wallpaper ${second.wallpaper.id}'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('immersive-viewer-close')));
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

  testWidgets('fills the preview letterbox with the wallpaper itself', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(tester, _details());

    // Detail's preview is a fixed-height pane, so a wide wallpaper strands a
    // dead black band above and below it. It is painted from the same
    // thumbnail the shelf already fetched — never a second request.
    final BlurredImageBackdrop backdrop = tester.widget<BlurredImageBackdrop>(
      find.byType(BlurredImageBackdrop),
    );
    expect(backdrop.imageUrl, 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg');
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
    "an ejected download folder says reconnect it, not couldn't download",
    (WidgetTester tester) async {
      final WallpaperDetails details = _details();
      final FakeImageStore imageStore = FakeImageStore(
        failure: const ImageStoreFailure(
          ImageStoreProblem.folderUnavailable,
        ),
      );
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

      expect(
        find.text(
          'Download folder unavailable. '
          'Reconnect the storage or pick another in Settings.',
        ),
        findsOneWidget,
      );
      expect(find.text("Couldn't download this wallpaper."), findsNothing);
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

  // The memory paying off: a run of private-library downloads offers to become
  // the default, and taking the offer writes the setting so the next plain tap
  // needs no long press at all.
  testWidgets('"Make this the default" persists the streak tier', (
    WidgetTester tester,
  ) async {
    final FakeSettingsRepository repository = FakeSettingsRepository(
      streaks: <Purity, DownloadDestinationStreak>{
        Purity.sfw: DownloadDestinationStreak(
          tier: StorageTier.appPrivate,
          length: 3,
        ),
      },
    );
    await _tallSurface(tester);
    await _pumpDetail(
      tester,
      _details(purity: Purity.sketchy),
      imageStore: FakeImageStore(),
      settingsRepository: repository,
    );

    await tester.longPress(find.bySemanticsLabel('Download'));
    await tester.pumpAndSettle();
    final Finder makeDefault = find.text('Make this the default for Sketchy');
    await tester.ensureVisible(makeDefault);
    await tester.tap(makeDefault);
    await tester.pumpAndSettle();

    // Sketchy writes the safe bucket — two knobs, not three.
    expect(repository.saved.sfwTier, StorageTier.appPrivate);
  });

  testWidgets('the download button warns before a not-safe wallpaper lands', (
    WidgetTester tester,
  ) async {
    // Sketchy is the case that stings, so it is the one pinned here: it routes
    // to the MediaStore-indexed gallery exactly like a safe wallpaper, the
    // long press that would send it elsewhere is invisible, and nothing else
    // on this screen tells the two apart at a glance.
    await _pumpDetail(tester, _details(purity: Purity.sketchy));

    final ColorScheme colors = Theme.of(
      tester.element(find.byType(WallpaperDetailScreen)),
    ).colorScheme;
    expect(_downloadIcon(tester).color, colors.error);
  });

  testWidgets('the download button stays quiet for a safe wallpaper', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(tester, _details());
    expect(_downloadIcon(tester).color, isNull);
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

  testWidgets('View on Wallhaven hands the page to the browser', (
    WidgetTester tester,
  ) async {
    await _tallSurface(tester);
    final FakeExternalLink links = FakeExternalLink();
    final WallpaperDetails details = _details();
    await _pumpDetail(tester, details, externalLink: links);

    await tester.tap(find.text('View on Wallhaven'));
    await tester.pumpAndSettle();

    expect(links.opened, <Uri>[details.wallpaper.pageUrl]);
  });

  testWidgets('a link that opens nothing says so, and no more', (
    WidgetTester tester,
  ) async {
    await _tallSurface(tester);
    final FakeExternalLink links = FakeExternalLink(
      failure: const ExternalLinkFailure(ExternalLinkProblem.unavailable),
    );
    await _pumpDetail(tester, _details(), externalLink: links);

    await tester.tap(find.text('View on Wallhaven'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't open the link."), findsOneWidget);
  });

  testWidgets('swiping the preview selects the next wallpaper', (
    WidgetTester tester,
  ) async {
    final WallpaperDetails first = _details();
    final WallpaperDetails second = _otherDetails();
    final GallerySessionController<Wallpaper> gallery = _twoItemGallery(
      first,
      second,
    );
    await _pumpDetail(
      tester,
      first,
      gallerySession: gallery,
      api: _detailsApi(first, second),
    );

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    // The session moved, and the screen rebound to it: the preview names the
    // new image.
    expect(gallery.selectedItem, second.wallpaper);
    expect(
      find.bySemanticsLabel('Wallpaper ${second.wallpaper.id}'),
      findsOneWidget,
    );
  });

  testWidgets('the chevrons step forward and back through the shelf', (
    WidgetTester tester,
  ) async {
    final WallpaperDetails first = _details();
    final WallpaperDetails second = _otherDetails();
    final GallerySessionController<Wallpaper> gallery = _twoItemGallery(
      first,
      second,
    );
    await _pumpDetail(
      tester,
      first,
      gallerySession: gallery,
      api: _detailsApi(first, second),
      disableAnimations: true,
    );

    await tester.tap(find.byKey(const Key('detail-next')));
    await tester.pumpAndSettle();
    expect(gallery.selectedItem, second.wallpaper);

    await tester.tap(find.byKey(const Key('detail-previous')));
    await tester.pumpAndSettle();
    expect(gallery.selectedItem, first.wallpaper);
  });

  testWidgets('a chevron appears only where there is a neighbour', (
    WidgetTester tester,
  ) async {
    final WallpaperDetails first = _details();
    final WallpaperDetails second = _otherDetails();
    final GallerySessionController<Wallpaper> gallery = _twoItemGallery(
      first,
      second,
    );
    await _pumpDetail(
      tester,
      first,
      gallerySession: gallery,
      api: _detailsApi(first, second),
      disableAnimations: true,
    );

    // First of two: nowhere back, somewhere forward.
    expect(find.byKey(const Key('detail-previous')), findsNothing);
    expect(find.byKey(const Key('detail-next')), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-next')));
    await tester.pumpAndSettle();

    // Last of two: the mirror image.
    expect(find.byKey(const Key('detail-previous')), findsOneWidget);
    expect(find.byKey(const Key('detail-next')), findsNothing);
  });

  testWidgets('the pager catches up when the session moves from outside', (
    WidgetTester tester,
  ) async {
    // The fullscreen viewer pages the shared session while Detail sits behind
    // it; on return the pager must be on the selected image, not where the last
    // swipe left it. Driving the session directly stands in for that path.
    final WallpaperDetails first = _details();
    final WallpaperDetails second = _otherDetails();
    final GallerySessionController<Wallpaper> gallery = _twoItemGallery(
      first,
      second,
    );
    await _pumpDetail(
      tester,
      first,
      gallerySession: gallery,
      api: _detailsApi(first, second),
      disableAnimations: true,
    );

    gallery.selectNext();
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Wallpaper ${second.wallpaper.id}'),
      findsOneWidget,
    );
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

  // Bounded pumps, never pumpAndSettle: the detail screen keeps a perpetual
  // animation (why _pumpDetail settles by hand), so waiting for quiescence with
  // a delete toast in flight never returns.
  group('Delete from device (J)', () {
    testWidgets('is offered only for a wallpaper already downloaded', (
      WidgetTester tester,
    ) async {
      await _pumpDetail(tester, _details());
      await tester.pump();

      expect(find.byKey(const Key('detail-delete')), findsNothing);
    });

    testWidgets('deletes a downloaded gallery file and retires its button', (
      WidgetTester tester,
    ) async {
      final WallpaperDetails details = _details();
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_recordFor(details.wallpaper)],
      );
      final FakeImageStore imageStore = FakeImageStore();
      await _pumpDetail(
        tester,
        details,
        history: history,
        imageStore: imageStore,
      );
      await tester.pump();

      expect(find.byKey(const Key('detail-delete')), findsOneWidget);
      await tester.tap(find.byKey(const Key('detail-delete')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Gallery on API 30+: the OS prompt (the fake) confirms, not tela.
      expect(find.text('Delete from device?'), findsNothing);
      expect(imageStore.deletedLocations, hasLength(1));
      expect(history.recorded, isEmpty);
      // The wallpaper is still browsable; only its download is gone, so the
      // button that offered the delete retires itself.
      expect(find.byKey(const Key('detail-delete')), findsNothing);
    });

    testWidgets('a files-tier delete asks first, and names the file', (
      WidgetTester tester,
    ) async {
      final WallpaperDetails details = _details();
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[
          _recordFor(details.wallpaper, tier: StorageTier.filesOutsideGallery),
        ],
      );
      final FakeImageStore imageStore = FakeImageStore();
      await _pumpDetail(
        tester,
        details,
        history: history,
        imageStore: imageStore,
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('detail-delete')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Delete from device?'), findsOneWidget);
      expect(imageStore.deletedLocations, isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(imageStore.deletedLocations, hasLength(1));
      expect(history.recorded, isEmpty);
    });
  });
}

DownloadRecord _recordFor(
  Wallpaper wallpaper, {
  StorageTier tier = StorageTier.sharedGallery,
}) => DownloadRecord(
  wallpaper: wallpaper,
  tier: tier,
  location: Uri.parse('content://media/external/images/media/${wallpaper.id}'),
  downloadedAt: DateTime.utc(2026, 7, 14),
);

/// The action-bar download glyph, scoped so the fullscreen viewer's own
/// download button can never be the one that answers.
Icon _downloadIcon(WidgetTester tester) {
  return tester.widget<Icon>(
    find.descendant(
      of: find.bySemanticsLabel('Download'),
      matching: find.byIcon(Icons.download_outlined),
    ),
  );
}

/// A two-wallpaper Detail session, for the swipe and chevron paging tests.
GallerySessionController<Wallpaper> _twoItemGallery(
  WallpaperDetails first,
  WallpaperDetails second,
) {
  return GallerySessionController<Wallpaper>(
    identity: 'favorites',
    items: <Wallpaper>[first.wallpaper, second.wallpaper],
    initialIndex: 0,
  );
}

/// A fake API that answers full metadata for both wallpapers in the session, so
/// paging between them resolves rather than erroring.
FakeWallhavenApi _detailsApi(WallpaperDetails first, WallpaperDetails second) {
  return FakeWallhavenApi(
    detailsById: <String, WallpaperDetails>{
      first.wallpaper.id: first,
      second.wallpaper.id: second,
    },
  );
}

/// A viewport tall enough to show the whole compact metadata column without
/// scrolling — 800 wide keeps it under the 840dp two-pane breakpoint — so a
/// metadata action can be tapped where the default 600px surface hides it.
Future<void> _tallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _pumpDetail(
  WidgetTester tester,
  WallpaperDetails details, {
  FakeImageStore? imageStore,
  StorageSettings? settings,
  FakeSettingsRepository? settingsRepository,
  FakeWallpaperSharer? sharer,
  FakeTagBlocklistRepository? blocklist,
  FakeImmersiveSystemUi? immersiveSystemUi,
  FakeWallhavenApi? api,
  GallerySessionController<Wallpaper>? gallerySession,
  FakeWallpaperApplier? applier,
  FakeExternalLink? externalLink,
  FakeFavoritesRepository? favorites,
  FakeDownloadHistory? history,
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
          settingsRepository ?? FakeSettingsRepository(settings: settings),
        ),
        // The app bar now carries the favorites heart, so this screen reaches
        // the database. Left unbound, it opens the real one and leaks a timer.
        favoritesRepositoryProvider.overrideWithValue(
          favorites ?? FakeFavoritesRepository(),
        ),
        // Downloading records where the file landed — the same database again.
        downloadHistoryProvider.overrideWithValue(
          history ?? FakeDownloadHistory(),
        ),
        // The share button would otherwise reach the real method channel.
        wallpaperSharerProvider.overrideWithValue(
          sharer ?? FakeWallpaperSharer(),
        ),
        // So would the adjust button beside it.
        systemWallpaperEditorProvider.overrideWithValue(
          FakeSystemWallpaperEditor(),
        ),
        // Blocking a tag reaches the database too.
        tagBlocklistRepositoryProvider.overrideWithValue(
          blocklist ?? FakeTagBlocklistRepository(),
        ),
        if (imageStore != null)
          imageStoreProvider.overrideWithValue(imageStore),
        if (applier != null)
          wallpaperApplierProvider.overrideWithValue(applier),
        if (externalLink != null)
          externalLinkProvider.overrideWithValue(externalLink),
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
    source: SourceId.wallhaven,
    pageUrl: Uri.parse('https://wallhaven.cc/w/e7jvjd'),
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
  final Wallpaper wallpaper = Wallpaper(
    id: 'bbb222',
    source: SourceId.wallhaven,
    pageUrl: Uri.parse('https://wallhaven.cc/w/bbb222'),
    fullImageUrl: 'https://w.wallhaven.cc/full/bb/wallhaven-bbb222.jpg',
    thumbSmallUrl: 'https://th.wallhaven.cc/small/bb/bbb222.jpg',
    thumbLargeUrl: 'https://th.wallhaven.cc/lg/bb/bbb222.jpg',
    thumbOriginalUrl: 'https://th.wallhaven.cc/orig/bb/bbb222.jpg',
    resolution: const Resolution(2160, 3840),
    fileSizeBytes: 2048,
    purity: Purity.sfw,
    category: Category.general,
    colors: const <String>['#0066cc'],
  );
  return WallpaperDetails(
    wallpaper: wallpaper,
    ratio: '0.56',
    fileType: 'image/jpeg',
    tags: const <WallpaperTag>[WallpaperTag(id: 303, name: 'portrait')],
    uploader: const WallpaperUploader(
      username: 'second-uploader',
      group: 'User',
      avatarUrl: 'https://example.com/second-avatar.jpg',
    ),
    source: '',
    views: 12,
    favorites: 3,
  );
}
