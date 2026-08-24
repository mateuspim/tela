import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/shelf_swipe.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/detail/detail_preview_pager.dart';
import 'package:tela/features/detail/progressive_wallpaper_preview.dart';

import '../fakes/fake_immersive_system_ui.dart';

/// The pinch regression of 2026-08-11, pinned at the seam that caused it.
///
/// Reported from the device pass: pinch-to-zoom on Detail "sometimes doesn't
/// work — it keeps seeing it as one finger", while the same viewport zoomed
/// fine in fullscreen. The two surfaces differed only in how they paged, and
/// Detail's [PageView] put a horizontal drag recognizer in the arena against
/// the viewport's scale recognizer.
///
/// The *sometimes* is the whole bug and the reason for two pinch tests below: a
/// pinch whose fingers land together zoomed even before the fix, and a pinch
/// whose first finger drifts first did not move the scale off 1.0 at all. Only
/// the second one reproduces what was reported, so only it proves the fix.
void main() {
  testWidgets('a pinch zooms when both fingers land together', (
    WidgetTester tester,
  ) async {
    await _pumpPager(tester, _session());

    await _pinch(tester, staggered: false);

    expect(_zoomScale(tester), greaterThan(1));
  });

  testWidgets('a pinch zooms when the first finger moves first', (
    WidgetTester tester,
  ) async {
    // The reported failure. Before the fix this stayed at exactly 1.0: the
    // pager's drag recognizer had already won the arena on finger one, so the
    // scale recognizer was rejected before finger two ever arrived.
    await _pumpPager(tester, _session());

    await _pinch(tester, staggered: true);

    expect(
      _zoomScale(tester),
      greaterThan(1),
      reason: 'a drifting first finger must not cost the pinch its gesture',
    );
  });

  testWidgets('a one-finger swipe still turns the page', (
    WidgetTester tester,
  ) async {
    // The pager is unscrollable now, so paging is entirely ShelfSwipe's doing.
    // If this breaks, Detail is left with only its chevrons.
    final GallerySessionController<Wallpaper> session = _session();
    await _pumpPager(tester, session);

    await _swipe(tester, const Offset(-40, 0));
    expect(session.selectedIndex, 0, reason: 'too short to be a page turn');

    await _swipe(tester, const Offset(-200, 0));
    expect(session.selectedIndex, 1);

    await _swipe(tester, const Offset(200, 0));
    expect(session.selectedIndex, 0);
  });

  testWidgets('a swipe across a zoomed wallpaper is a pan, not a page turn', (
    WidgetTester tester,
  ) async {
    // Turning the page under a pan would throw away the position the user
    // worked to reach — the call the fullscreen viewer has always made.
    final GallerySessionController<Wallpaper> session = _session();
    await _pumpPager(tester, session);

    _zoom(tester).value = _scaledBy(2);
    await tester.pump();

    await _swipe(tester, const Offset(-200, 0));

    expect(session.selectedIndex, 0);
  });

  testWidgets('holding the wallpaper hands the one on screen to the copy', (
    WidgetTester tester,
  ) async {
    // The gesture reaches whichever wallpaper is selected, not the one the
    // pager started on — a hold after a swipe must not copy the last image.
    final List<String> held = <String>[];
    final GallerySessionController<Wallpaper> session = _session();
    await _pumpPager(
      tester,
      session,
      onHoldImage: (Wallpaper wallpaper) => held.add(wallpaper.id),
    );

    await _hold(tester);
    expect(held, <String>['one']);

    await _swipe(tester, const Offset(-200, 0));
    await _hold(tester);

    expect(held, <String>['one', 'two']);
  });

  testWidgets('an explicit wallpaper is held like any other', (
    WidgetTester tester,
  ) async {
    // The gesture carries no purity rule of its own — the copy is offered at
    // every purity (`shareOptionsFor`), and a hold that silently did nothing on
    // some wallpapers would read as a broken gesture rather than as a policy.
    final List<String> held = <String>[];
    await _pumpPager(
      tester,
      _session(purity: Purity.nsfw),
      onHoldImage: (Wallpaper wallpaper) => held.add(wallpaper.id),
    );

    await _hold(tester);

    expect(held, <String>['one']);
  });

  testWidgets('turning the page returns the wallpaper to fitted scale', (
    WidgetTester tester,
  ) async {
    final GallerySessionController<Wallpaper> session = _session();
    await _pumpPager(tester, session);

    _zoom(tester).value = _scaledBy(2);
    await tester.pump();

    // The chevron, not a swipe: a labelled control still selects while zoomed,
    // which is exactly why the reset cannot live in the swipe.
    await tester.tap(find.byKey(const Key('detail-next')));
    await tester.pumpAndSettle();

    expect(session.selectedIndex, 1);
    expect(_zoom(tester).value, Matrix4.identity());
  });

  testWidgets('an appended page leaves the current zoom alone', (
    WidgetTester tester,
  ) async {
    // The session notifies for growth as well as selection. Resetting on every
    // notification would fling the examined wallpaper back to fitted scale the
    // moment the shelf loaded its next page.
    final GallerySessionController<Wallpaper> session = _session();
    await _pumpPager(tester, session);

    final Matrix4 zoomed = _scaledBy(2);
    _zoom(tester).value = zoomed;
    await tester.pump();

    session.append(<Wallpaper>[_wallpaper('grown')]);
    await tester.pump();

    expect(_zoom(tester).value, zoomed);
  });

  testWidgets('a double tap zooms in, and a second one returns to fitted', (
    WidgetTester tester,
  ) async {
    // The gesture fullscreen always had. It could not exist in Detail until
    // the pager stopped owning the zoom state, so it lands with the pinch fix.
    await _pumpPager(tester, _session());

    await _doubleTap(tester, tester.getCenter(find.byType(PageView)));
    expect(_zoomScale(tester), greaterThan(1));

    await _doubleTap(tester, tester.getCenter(find.byType(PageView)));
    expect(_zoomScale(tester), closeTo(1, 0.001));
  });

  testWidgets('a double tap zooms around the point that was tapped', (
    WidgetTester tester,
  ) async {
    // Zooming around the centre regardless of the thumb sends whatever the
    // user was looking at off the edge of the screen.
    await _pumpPager(tester, _session());
    final Rect pager = tester.getRect(find.byType(PageView));

    await _doubleTap(tester, pager.centerLeft + const Offset(24, 0));

    final Matrix4 zoomed = _zoom(tester).value;
    expect(zoomed.getMaxScaleOnAxis(), greaterThan(1));
    expect(
      zoomed.entry(0, 3),
      isNot(closeTo(0, 0.001)),
      reason: 'an off-centre focal point has to translate the image',
    );
  });

  testWidgets('turning the page mid-zoom does not carry the zoom across', (
    WidgetTester tester,
  ) async {
    // The transition writes a frame at a time; a chevron during one used to
    // reset the controller and then have the rest of the tween written over
    // it, landing the next wallpaper at the previous one's scale.
    final GallerySessionController<Wallpaper> session = _session();
    await _pumpPager(tester, session);

    await _startDoubleTap(tester, tester.getCenter(find.byType(PageView)));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byKey(const Key('detail-next')));
    await tester.pumpAndSettle();

    expect(session.selectedIndex, 1);
    expect(_zoom(tester).value, Matrix4.identity());
  });

  testWidgets('only the page on screen is wired to the zoom state', (
    WidgetTester tester,
  ) async {
    // Shared, the neighbour would sit pre-zoomed under the turn: it is built
    // while the animation exposes it, before it is ever the selection.
    await _pumpPager(tester, _session());

    await tester.tap(find.byKey(const Key('detail-next')));
    // Two pumps, not one: the first starts the turn's ticker, the second lands
    // partway through it, which is the only moment both pages exist.
    await tester.pump(_frame);
    await tester.pump(const Duration(milliseconds: 60));

    final List<ProgressiveWallpaperPreview> pages = _pages(tester);
    expect(pages.length, greaterThan(1), reason: 'mid-turn, two are on screen');
    expect(
      pages
          .where(
            (ProgressiveWallpaperPreview page) =>
                page.transformationController != null,
          )
          .length,
      1,
    );
    await tester.pumpAndSettle();
  });

  /// The ⛶ in the corner was hard to find and hard to hit (owner, 2026-08-17),
  /// so the picture itself is the target now. The button stays — a tap on an
  /// image is invisible to a screen reader, so it is never the only way in.
  testWidgets('a tap on the wallpaper is the way into fullscreen', (
    WidgetTester tester,
  ) async {
    await _pumpPager(tester, _session());

    final List<ProgressiveWallpaperPreview> pages = _pages(tester);
    expect(pages.single.onTap, isNotNull);
  });

  testWidgets('only the page on screen answers a tap', (
    WidgetTester tester,
  ) async {
    await _pumpPager(tester, _session());

    await tester.tap(find.byKey(const Key('detail-next')));
    await tester.pump(_frame);
    await tester.pump(const Duration(milliseconds: 60));

    final List<ProgressiveWallpaperPreview> pages = _pages(tester);
    expect(pages.length, greaterThan(1), reason: 'mid-turn, two are on screen');
    expect(
      pages
          .where((ProgressiveWallpaperPreview page) => page.onTap != null)
          .length,
      1,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('an upward throw on the wallpaper reaches the facts', (
    WidgetTester tester,
  ) async {
    // The grip is a band at the very foot of the screen; the wallpaper above
    // it is everything else. "the details button is kinda hit or miss on
    // portrait" — the owner, 2026-08-24.
    int revealed = 0;
    await _pumpPager(
      tester,
      _session(),
      onRevealDetails: () => revealed++,
    );

    await _swipe(tester, const Offset(0, -40));
    expect(revealed, 0, reason: 'too short to be a throw');

    await _swipe(tester, const Offset(0, -200));
    expect(revealed, 1);
  });

  testWidgets('an upward throw never also turns the page', (
    WidgetTester tester,
  ) async {
    // One finger does one thing. A diagonal resolves to whichever axis it
    // travelled furthest along, and the two readings must stay exclusive.
    final GallerySessionController<Wallpaper> session = _session();
    int revealed = 0;
    await _pumpPager(tester, session, onRevealDetails: () => revealed++);

    await _swipe(tester, const Offset(-90, -200));

    expect(revealed, 1);
    expect(session.selectedIndex, 0);
  });

  testWidgets('an upward drag across a zoomed wallpaper is a pan', (
    WidgetTester tester,
  ) async {
    // Same rule the page turn and the dismiss already follow: on a magnified
    // image a vertical drag is the user moving around it, and raising a sheet
    // over it would throw away the position they worked to reach.
    int revealed = 0;
    await _pumpPager(
      tester,
      _session(),
      onRevealDetails: () => revealed++,
    );
    await _doubleTap(tester, tester.getCenter(find.byType(PageView)));

    await _swipe(tester, const Offset(0, -200));

    expect(revealed, 0);
  });
}

/// Drives two fingers apart from the centre, optionally letting the first one
/// travel alone first — which is what made the bug intermittent.
Future<void> _pinch(WidgetTester tester, {required bool staggered}) async {
  final Offset centre = tester.getCenter(find.byType(PageView));
  final TestGesture left = await tester.startGesture(centre - _apart);
  if (staggered) await _travel(tester, left, const Offset(-10, 0), 3);
  final TestGesture right = await tester.startGesture(centre + _apart);
  await tester.pump(_frame);
  for (int step = 0; step < 10; step++) {
    await left.moveBy(const Offset(-8, 0));
    await right.moveBy(const Offset(8, 0));
    await tester.pump(_frame);
  }
  await left.up();
  await right.up();
  await tester.pumpAndSettle();
}

/// A one-finger drag of [travel], delivered in steps so it reads as a drag
/// rather than a teleport.
Future<void> _swipe(WidgetTester tester, Offset travel) async {
  final TestGesture finger = await tester.startGesture(
    tester.getCenter(find.byType(PageView)),
  );
  await _travel(tester, finger, travel / 8, 8);
  await finger.up();
  await tester.pumpAndSettle();
}

/// Two taps close enough together to read as one double tap, left running so a
/// test can act during the zoom transition they start.
Future<void> _startDoubleTap(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(kDoubleTapMinTime);
  await tester.tapAt(at);
  await tester.pump();
}

/// [_startDoubleTap], carried through to a settled zoom.
Future<void> _doubleTap(WidgetTester tester, Offset at) async {
  await _startDoubleTap(tester, at);
  await tester.pumpAndSettle();
}

Future<void> _travel(
  WidgetTester tester,
  TestGesture gesture,
  Offset step,
  int steps,
) async {
  for (int taken = 0; taken < steps; taken++) {
    await gesture.moveBy(step);
    await tester.pump(_frame);
  }
}

const Duration _frame = Duration(milliseconds: 16);

/// Far enough apart to read as two fingers rather than one noisy contact.
const Offset _apart = Offset(20, 0);

Matrix4 _scaledBy(double scale) =>
    Matrix4.identity()..scaleByDouble(scale, scale, 1, 1);

List<ProgressiveWallpaperPreview> _pages(WidgetTester tester) {
  return tester
      .widgetList<ProgressiveWallpaperPreview>(
        find.byType(ProgressiveWallpaperPreview, skipOffstage: false),
      )
      .toList();
}

/// The controller handed to the selected page — the one thing that tells the
/// pager it is zoomed.
TransformationController _zoom(WidgetTester tester) {
  return _pages(tester)
      .map(
        (ProgressiveWallpaperPreview page) => page.transformationController,
      )
      .whereType<TransformationController>()
      .single;
}

double _zoomScale(WidgetTester tester) =>
    _zoom(tester).value.getMaxScaleOnAxis();

Future<void> _hold(WidgetTester tester) async {
  final TestGesture finger = await tester.startGesture(
    tester.getCenter(find.byType(ProgressiveWallpaperPreview).first),
  );
  await tester.pump(ShelfSwipe.holdDuration + const Duration(milliseconds: 8));
  await finger.up();
  await tester.pumpAndSettle();
}

GallerySessionController<Wallpaper> _session({Purity purity = Purity.sfw}) {
  return GallerySessionController<Wallpaper>(
    identity: 'detail-pager-test',
    items: <Wallpaper>[
      _wallpaper('one', purity: purity),
      _wallpaper('two', purity: purity),
      _wallpaper('tre', purity: purity),
    ],
    initialIndex: 0,
  );
}

Future<void> _pumpPager(
  WidgetTester tester,
  GallerySessionController<Wallpaper> session, {
  void Function(Wallpaper wallpaper)? onHoldImage,
  VoidCallback? onRevealDetails,
}) async {
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: DetailPreviewPager(
            gallery: session,
            systemUi: FakeImmersiveSystemUi(),
            onHoldImage: onHoldImage,
            onRevealDetails: onRevealDetails,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Wallpaper _wallpaper(String id, {Purity purity = Purity.sfw}) => Wallpaper(
  id: id,
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
  fullImageUrl: 'https://w.wallhaven.cc/full/$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/$id.jpg',
  resolution: const Resolution(1080, 2400),
  fileSizeBytes: 1024,
  purity: purity,
  category: Category.general,
  colors: const <String>[],
);
