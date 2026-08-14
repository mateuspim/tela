import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/theme.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/ambient_wallpaper_theme.dart';
import 'package:tela/core/ui/blurred_image_backdrop.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/gallery_viewport.dart';
import 'package:tela/core/ui/shelf_swipe.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/clipboard_confirmation.dart';
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
import 'package:tela/domain/ports/wallpaper_source.dart';
import 'package:tela/features/detail/wallpaper_detail_screen.dart';
import 'package:tela/features/favorites/favorite_button.dart';

import '../fakes/fake_dominant_color.dart';
import '../fakes/fake_download_history.dart';
import '../fakes/fake_external_link.dart';
import '../fakes/fake_favorites_repository.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_immersive_system_ui.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_system_wallpaper_editor.dart';
import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallpaper_applier.dart';
import '../fakes/fake_wallpaper_sharer.dart';
import '../fakes/fake_wallpaper_source.dart';

void main() {
  testWidgets('tints a palette-less wallpaper from its own pixels', (
    WidgetTester tester,
  ) async {
    // Konachan reports no colours at all, so without this its whole catalogue
    // would be the one source that never tints. The colour is read from the
    // thumbnail the shelf already fetched.
    final FakeDominantColor colours = FakeDominantColor(colour: '#ff6600');
    await _pumpDetail(
      tester,
      _details(sourceId: SourceId.konachan, colors: const <String>[]),
      dominantColor: colours,
    );
    await tester.pumpAndSettle();

    expect(
      _detailScheme(tester).primary,
      TelaTheme.ambient(
        _untintedScheme(tester),
        const Color(0xFFFF6600),
      ).colorScheme.primary,
    );
  });

  testWidgets('never reads pixels when the source reported a palette', (
    WidgetTester tester,
  ) async {
    // The cost control. Wallhaven answers this in its own JSON, so a decode
    // there is work spent re-deriving something already known.
    final FakeDominantColor colours = FakeDominantColor(colour: '#ff6600');
    await _pumpDetail(tester, _details(), dominantColor: colours);
    await tester.pumpAndSettle();

    expect(colours.asked, isEmpty);
  });

  testWidgets('stays untinted when the pixels have no colour either', (
    WidgetTester tester,
  ) async {
    // A greyscale Konachan wallpaper: no palette, and nothing in the image to
    // fall back to. Absent, never grey — the same answer the Wallhaven path
    // gives, which is the point of sharing `canTint`.
    await _pumpDetail(
      tester,
      _details(sourceId: SourceId.konachan, colors: const <String>[]),
      dominantColor: FakeDominantColor(),
    );
    await tester.pumpAndSettle();

    expect(_detailScheme(tester), same(_untintedScheme(tester)));
  });

  testWidgets('keeps the fullscreen button clear of the floating bar', (
    WidgetTester tester,
  ) async {
    // The phone layout runs the wallpaper behind the app bar, which put the
    // preview's own fullscreen control underneath the bar's actions — a tap on
    // fullscreen opening the share sheet instead. Found by eight existing
    // tests going red at once, not by looking.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDetail(tester, _details());

    final Rect fullscreen = tester.getRect(
      find.byTooltip('View wallpaper full screen'),
    );
    final Rect bar = tester.getRect(find.byType(AppBar));
    expect(fullscreen.top, greaterThanOrEqualTo(bar.bottom));
  });

  testWidgets("paints itself in the wallpaper's own colour", (
    WidgetTester tester,
  ) async {
    await _pumpDetail(tester, _details());

    // The whole scheme travels, not just an accent role: the surface a fixed
    // accent would have left on Material You's neutrals is the thing that
    // makes the tint read as the image lighting the page rather than as paint.
    expect(
      _detailScheme(tester).primary,
      TelaTheme.ambient(
        _untintedScheme(tester),
        const Color(0xFF660000),
      ).colorScheme.primary,
    );
  });

  testWidgets('carries the tint to the wallpaper stepped to', (
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
      source: _detailsApi(first, second),
      disableAnimations: true,
    );
    final Color opening = _detailScheme(tester).primary;

    await tester.tap(find.byKey(const Key('detail-next')));
    await tester.pumpAndSettle();

    // The screen already rebuilds on the session's selection; this proves the
    // tint is one of the things that rebuild carries, so a swipe repaints the
    // surround instead of stranding it on the wallpaper left behind.
    expect(_detailScheme(tester).primary, isNot(opening));
    expect(
      _detailScheme(tester).primary,
      TelaTheme.ambient(
        _untintedScheme(tester),
        const Color(0xFF0066CC),
      ).colorScheme.primary,
    );
  });

  testWidgets("tints the wide layout's information pane too", (
    WidgetTester tester,
  ) async {
    // The pane paints itself from an explicit `Theme.of` read, which resolves
    // against this State's *own* context — outside the theme `build` returns.
    // The Builder is what puts it below instead of beside; delete the Builder
    // and this pane alone stays on the untinted surface while everything that
    // resolves its own theme moves, which reads as a rendering bug.
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDetail(tester, _details());

    final ColoredBox pane = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byKey(const Key('detail-information-pane')),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(pane.color, _detailScheme(tester).surfaceContainerLow);
    expect(pane.color, isNot(_untintedScheme(tester).surfaceContainerLow));
  });

  testWidgets('stays on the ordinary theme for a greyscale wallpaper', (
    WidgetTester tester,
  ) async {
    // Also every Konachan wallpaper, by the same path: its mapper reports no
    // colours at all. The tint is absent there, never grey.
    await _pumpDetail(
      tester,
      _details(colors: const <String>['#000000', '#ffffff']),
    );

    // Asserted as "inside equals outside" rather than "no AnimatedTheme
    // below": Material scatters its own 200ms ones through buttons and cards,
    // so counting them measures the framework, not this widget.
    expect(_detailScheme(tester), same(_untintedScheme(tester)));
  });

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

  testWidgets('fullscreen Open details returns to the selected Detail', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(tester, _details());

    await tester.tap(find.byTooltip('View wallpaper full screen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('immersive-viewer-open-details')));
    await tester.pumpAndSettle();

    expect(find.byType(WallpaperDetailScreen), findsOneWidget);
    expect(find.text('Set wallpaper'), findsOneWidget);
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
      final FakeWallpaperSource source = FakeWallpaperSource(
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
        source: source,
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
    expect(find.text('Copy image'), findsOneWidget);
  });

  testWidgets('copying the image routes it to the sharer and says so', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSharer sharer = FakeWallpaperSharer();
    final WallpaperDetails details = _details();
    await _pumpDetail(tester, details, sharer: sharer);

    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy image'));
    await tester.pumpAndSettle();

    expect(sharer.copiedImages, hasLength(1));
    expect(
      sharer.copiedImages.single.source,
      Uri.parse(details.wallpaper.fullImageUrl),
    );
    expect(find.text('Image copied.'), findsOneWidget);
  });

  testWidgets('a copy Android already confirmed is not confirmed twice', (
    WidgetTester tester,
  ) async {
    // From Android 13 the platform shows its own clipboard preview, and a toast
    // of tela's on top of it is the same news twice.
    final FakeWallpaperSharer sharer = FakeWallpaperSharer(
      confirmation: ClipboardConfirmation.system,
    );
    await _pumpDetail(tester, _details(), sharer: sharer);

    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy image'));
    await tester.pumpAndSettle();

    expect(sharer.copiedImages, hasLength(1));
    expect(find.text('Image copied.'), findsNothing);
  });

  testWidgets('holding the preview copies the wallpaper', (
    WidgetTester tester,
  ) async {
    // The gesture the share sheet's Copy image tile exists beside: the whole
    // point of it is not opening a sheet at all.
    final FakeWallpaperSharer sharer = FakeWallpaperSharer();
    final WallpaperDetails details = _details();
    await _pumpDetail(tester, details, sharer: sharer);

    await _holdPreview(tester);

    expect(sharer.copiedImages, hasLength(1));
    expect(
      sharer.copiedImages.single.source,
      Uri.parse(details.wallpaper.fullImageUrl),
    );
    expect(find.text('Image copied.'), findsOneWidget);
  });

  testWidgets('holding the fullscreen image copies it too', (
    WidgetTester tester,
  ) async {
    // The surface where the wallpaper is actually being examined, and the one
    // whose only other route to a copy is closing out of it.
    final FakeWallpaperSharer sharer = FakeWallpaperSharer();
    await _pumpDetail(tester, _details(), sharer: sharer);

    await tester.tap(find.byTooltip('View wallpaper full screen'));
    await tester.pumpAndSettle();
    await _holdPreview(tester);

    expect(sharer.copiedImages, hasLength(1));
  });

  testWidgets('holding an explicit wallpaper copies it, marked sensitive', (
    WidgetTester tester,
  ) async {
    // Allowed at every purity since 2026-08-13. The flag is the part that must
    // not be lost on the way through the screen: it is what keeps an explicit
    // thumbnail out of Android's clipboard preview.
    final FakeWallpaperSharer sharer = FakeWallpaperSharer();
    await _pumpDetail(tester, _details(purity: Purity.nsfw), sharer: sharer);

    await _holdPreview(tester);

    expect(sharer.copiedImages, hasLength(1));
    expect(sharer.copiedImages.single.sensitive, isTrue);
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
    // The copy is not withheld with it — see `shareOptionsFor` for why the two
    // parted company.
    expect(find.text('Copy image'), findsOneWidget);
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

  testWidgets('Konachan detail and share copy name Konachan', (
    WidgetTester tester,
  ) async {
    await _tallSurface(tester);
    final WallpaperDetails details = _details(sourceId: SourceId.konachan);
    await _pumpDetail(
      tester,
      details,
      source: FakeWallpaperSource(
        id: SourceId.konachan,
        displayName: 'Konachan',
        capabilities: narrowCapabilities,
        details: details,
      ),
    );

    expect(find.text('View on Konachan'), findsOneWidget);
    expect(find.textContaining('View on Wallhaven'), findsNothing);

    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();

    expect(
      find.text('The Konachan page for this wallpaper.'),
      findsOneWidget,
    );
    expect(find.textContaining('The Wallhaven page'), findsNothing);
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
      source: _detailsApi(first, second),
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
      source: _detailsApi(first, second),
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
      source: _detailsApi(first, second),
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
      source: _detailsApi(first, second),
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
        wallhavenSourceProvider.overrideWithValue(
          FakeWallpaperSource(details: details),
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

    testWidgets('Move to private is gated the same way the delete is', (
      WidgetTester tester,
    ) async {
      // Both read `_downloadedRecord()`, which never sees an explicit or
      // app-private download — so neither action can disclose on this ungated
      // screen that such a download exists. A second gate written for the move
      // would be a second chance to get that wrong.
      await _pumpDetail(tester, _details());
      await tester.pump();

      expect(find.byKey(const Key('detail-move-to-private')), findsNothing);
    });

    testWidgets('Move to private confirms, then retires both buttons', (
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

      await tester.tap(find.byKey(const Key('detail-move-to-private')));
      await tester.pump();
      await tester.pump();

      // Unlike the gallery delete, tela always asks here: the trip is one-way,
      // and the OS prompt that follows says nothing about where the file goes.
      expect(find.textContaining('private library?'), findsOneWidget);
      await tester.tap(find.text('Move to private').last);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(imageStore.copies.single.tier, StorageTier.appPrivate);
      // The history row went with it — a private download is never recorded —
      // so both buttons retire and the screen offers a plain download again.
      expect(await history.downloads(), isEmpty);
      expect(find.byKey(const Key('detail-move-to-private')), findsNothing);
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
FakeWallpaperSource _detailsApi(
  WallpaperDetails first,
  WallpaperDetails second,
) {
  return FakeWallpaperSource(
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

/// Rests a finger on the image long enough for [ShelfSwipe] to call it a hold.
///
/// Targets the viewport's own image frame rather than the screen centre: Detail
/// is a column, and the centre of it is metadata on a tall layout.
Future<void> _holdPreview(WidgetTester tester) async {
  final TestGesture finger = await tester.startGesture(
    tester.getCenter(find.byKey(GalleryViewport.imageFrameKey).first),
  );
  await tester.pump(ShelfSwipe.holdDuration + const Duration(milliseconds: 8));
  await finger.up();
  await tester.pumpAndSettle();
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
  FakeWallpaperSource? source,
  GallerySessionController<Wallpaper>? gallerySession,
  FakeWallpaperApplier? applier,
  FakeExternalLink? externalLink,
  FakeFavoritesRepository? favorites,
  FakeDownloadHistory? history,
  FakeDominantColor? dominantColor,
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallpaperSourcesProvider.overrideWithValue(<WallpaperSource>[
          source ??
              FakeWallpaperSource(
                id: details.wallpaper.source,
                displayName: details.wallpaper.source == SourceId.konachan
                    ? 'Konachan'
                    : 'Wallhaven',
                details: details,
              ),
        ]),
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
        // Bound always: a source with no palette reaches this port on build,
        // and the real one decodes a file off the disk cache.
        dominantColorProvider.overrideWithValue(
          dominantColor ?? FakeDominantColor(),
        ),
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

WallpaperDetails _details({
  Purity purity = Purity.sfw,
  SourceId sourceId = SourceId.wallhaven,
  List<String> colors = const <String>['#660000'],
}) {
  final bool konachan = sourceId == SourceId.konachan;
  final String id = konachan ? '406484' : 'e7jvjd';
  final Wallpaper wallpaper = Wallpaper(
    id: id,
    source: sourceId,
    pageUrl: Uri.parse(
      konachan
          ? 'https://konachan.net/post/show/$id'
          : 'https://wallhaven.cc/w/$id',
    ),
    fullImageUrl: konachan
        ? 'https://konachan.com/image/$id.jpg'
        : 'https://w.wallhaven.cc/full/e7/wallhaven-$id.jpg',
    thumbSmallUrl: konachan
        ? 'https://konachan.com/preview/$id.jpg'
        : 'https://th.wallhaven.cc/small/e7/$id.jpg',
    thumbLargeUrl: konachan
        ? 'https://konachan.com/sample/$id.jpg'
        : 'https://th.wallhaven.cc/lg/e7/$id.jpg',
    thumbOriginalUrl: konachan
        ? 'https://konachan.com/preview/$id.jpg'
        : 'https://th.wallhaven.cc/orig/e7/$id.jpg',
    resolution: const Resolution(3840, 2160),
    fileSizeBytes: 1048576,
    purity: purity,
    category: Category.general,
    colors: colors,
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

/// The scheme the Detail screen actually renders under — the ambient one, which
/// therefore exists only *below* the wrapper and never at the level the screen
/// was pumped at. `MaterialApp` builds an `AnimatedTheme` of its own, so the
/// finder says whose.
ColorScheme _detailScheme(WidgetTester tester) => Theme.of(
  tester.element(
    find
        .descendant(
          of: find.byType(AmbientWallpaperTheme),
          matching: find.byType(Scaffold),
        )
        .first,
  ),
).colorScheme;

/// The theme the screen would have worn with no wallpaper to tint it — read
/// from just *above* the wrapper, which is the only place it survives.
ColorScheme _untintedScheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(AmbientWallpaperTheme))).colorScheme;
