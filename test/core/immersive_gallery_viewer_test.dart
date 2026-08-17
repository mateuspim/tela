import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_viewport.dart';
import 'package:tela/core/ui/gallery_zoom_controller.dart';
import 'package:tela/core/ui/immersive_chrome_palette.dart';
import 'package:tela/core/ui/immersive_gallery_viewer.dart';

import '../fakes/fake_immersive_system_ui.dart';

void main() {
  testWidgets('double tap zooms and double tap again resets', (
    WidgetTester tester,
  ) async {
    final GalleryZoomController zoomController = GalleryZoomController();
    addTearDown(zoomController.dispose);
    await _pumpViewer(
      tester,
      zoomController: zoomController,
      disableAnimations: true,
    );

    await _doubleTap(tester, find.byType(GalleryViewport));
    await tester.pump();

    expect(zoomController.isZoomed, isTrue);
    expect(find.bySemanticsLabel('Reset zoom'), findsOneWidget);

    await _doubleTap(tester, find.byType(GalleryViewport));
    await tester.pump();

    expect(zoomController.isZoomed, isFalse);
    expect(find.bySemanticsLabel('Zoom in'), findsOneWidget);
  });

  testWidgets('visible control zooms and resets without a gesture', (
    WidgetTester tester,
  ) async {
    final GalleryZoomController zoomController = GalleryZoomController();
    addTearDown(zoomController.dispose);
    await _pumpViewer(
      tester,
      zoomController: zoomController,
      disableAnimations: true,
    );

    await tester.tap(find.byKey(const Key('immersive-viewer-zoom')));
    await tester.pump();
    expect(zoomController.isZoomed, isTrue);

    await tester.tap(find.byKey(const Key('immersive-viewer-zoom')));
    await tester.pump();
    expect(zoomController.isZoomed, isFalse);
  });

  testWidgets('pinch zooms and a one-finger drag pans the image', (
    WidgetTester tester,
  ) async {
    final GalleryZoomController zoomController = GalleryZoomController();
    addTearDown(zoomController.dispose);
    await _pumpViewer(tester, zoomController: zoomController);

    final TestGesture left = await tester.startGesture(
      const Offset(380, 300),
      pointer: 1,
    );
    final TestGesture right = await tester.startGesture(
      const Offset(420, 300),
      pointer: 2,
    );
    await tester.pump();
    await left.moveTo(const Offset(320, 300));
    await right.moveTo(const Offset(480, 300));
    await tester.pump();
    await left.up();
    await right.up();

    expect(zoomController.isZoomed, isTrue);
    final double translationBefore = zoomController
        .transformationController
        .value
        .entry(0, 3);

    await tester.drag(find.byType(GalleryViewport), const Offset(40, 0));
    await tester.pump();

    expect(
      zoomController.transformationController.value.entry(0, 3),
      isNot(translationBefore),
    );
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('single tap toggles transient viewer chrome', (
    WidgetTester tester,
  ) async {
    await _pumpViewer(tester);

    await tester.tapAt(const Offset(400, 300));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();

    AnimatedOpacity chrome = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('immersive-viewer-chrome')),
    );
    expect(chrome.opacity, 0);
    expect(find.bySemanticsLabel('Show viewer controls'), findsOneWidget);

    await tester.tapAt(const Offset(400, 300));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    chrome = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('immersive-viewer-chrome')),
    );
    expect(chrome.opacity, 1);
  });

  // Tapping the image was the only way to hide the controls, which is not a
  // thing anyone finds by looking.
  testWidgets('an explicit button hides the chrome, and tap brings it back', (
    WidgetTester tester,
  ) async {
    await _pumpViewer(tester);

    await tester.tap(find.byKey(const Key('immersive-viewer-hide-chrome')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const Key('immersive-viewer-chrome')),
          )
          .opacity,
      0,
    );

    // The button hides the row it lives in, so the canvas has to be the way
    // back — otherwise this control is a one-way door out of the chrome.
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const Key('immersive-viewer-chrome')),
          )
          .opacity,
      1,
    );
  });

  testWidgets('the hide-chrome button is reachable and labelled', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pumpViewer(tester);

    // Scoped to the button. The canvas carries the same label — tapping the
    // image is the other way to hide the chrome — so an unscoped finder
    // matched *it* and passed even while the button itself was unlabelled,
    // which is exactly what it was silently doing before the chrome was
    // quietened (2026-07-19).
    expect(
      find.descendant(
        of: find.byKey(const Key('immersive-viewer-hide-chrome')),
        matching: find.bySemanticsLabel('Hide viewer controls'),
      ),
      findsOneWidget,
    );
    final Size target = tester.getSize(
      find.byKey(const Key('immersive-viewer-hide-chrome')),
    );
    expect(target.width, greaterThanOrEqualTo(48));
    expect(target.height, greaterThanOrEqualTo(48));
    semantics.dispose();
  });

  testWidgets('reduced motion makes chrome and zoom transitions instant', (
    WidgetTester tester,
  ) async {
    final GalleryZoomController zoomController = GalleryZoomController();
    addTearDown(zoomController.dispose);
    await _pumpViewer(
      tester,
      zoomController: zoomController,
      disableAnimations: true,
    );

    final AnimatedOpacity chrome = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('immersive-viewer-chrome')),
    );
    expect(chrome.duration, Duration.zero);

    await tester.tap(find.byKey(const Key('immersive-viewer-zoom')));
    expect(zoomController.isZoomed, isTrue);
    expect(
      zoomController.transformationController.value.getMaxScaleOnAxis(),
      2.5,
    );
  });

  testWidgets('controls expose labels and at least 48dp targets', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pumpViewer(tester);

    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    expect(find.bySemanticsLabel('Zoom in'), findsOneWidget);
    expect(find.bySemanticsLabel('Selected wallpaper'), findsOneWidget);

    for (final Key key in const <Key>[
      Key('immersive-viewer-close'),
      Key('immersive-viewer-zoom'),
      Key('immersive-viewer-previous'),
      Key('immersive-viewer-next'),
    ]) {
      final Size target = tester.getSize(find.byKey(key));
      expect(target.width, greaterThanOrEqualTo(48));
      expect(target.height, greaterThanOrEqualTo(48));
    }
    semantics.dispose();
  });

  testWidgets('shows position and disabled controls at loaded boundaries', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pumpViewer(
      tester,
      itemCount: 3,
      onNext: () {},
    );

    expect(find.bySemanticsLabel('1 of 3'), findsOneWidget);
    // Icon-only since the chrome was quietened, so the names live in
    // semantics rather than in visible text — the paging controls still
    // exist, because a swipe is not reachable by screen reader or switch.
    expect(find.bySemanticsLabel('Previous'), findsOneWidget);
    expect(find.bySemanticsLabel('Next'), findsOneWidget);
    final IconButton previous = tester.widget<IconButton>(
      find.byKey(const Key('immersive-viewer-previous')),
    );
    final IconButton next = tester.widget<IconButton>(
      find.byKey(const Key('immersive-viewer-next')),
    );
    expect(previous.onPressed, isNull);
    expect(next.onPressed, isNotNull);
    semantics.dispose();
  });

  testWidgets('swipe and keyboard arrows use the same navigation', (
    WidgetTester tester,
  ) async {
    int previous = 0;
    int next = 0;
    await _pumpViewer(
      tester,
      position: 2,
      itemCount: 3,
      onPrevious: () => previous++,
      onNext: () => next++,
    );

    await tester.fling(
      find.byType(GalleryViewport),
      const Offset(-300, 0),
      800,
    );
    await tester.pump();
    expect(next, 1);

    await tester.fling(find.byType(GalleryViewport), const Offset(300, 0), 800);
    await tester.pump();
    expect(previous, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(next, 2);
    expect(previous, 2);
  });

  // Named for keys, not "horizontal input": the chrome's Next button is
  // horizontal input too and deliberately does the opposite, which the test
  // below this one pins.
  testWidgets('keyboard arrows pan instead of paging while zoomed', (
    WidgetTester tester,
  ) async {
    int next = 0;
    final GalleryZoomController zoomController = GalleryZoomController();
    addTearDown(zoomController.dispose);
    await _pumpViewer(
      tester,
      zoomController: zoomController,
      disableAnimations: true,
      itemCount: 2,
      onNext: () => next++,
    );
    await tester.tap(find.byKey(const Key('immersive-viewer-zoom')));
    await tester.pump();
    final double before = zoomController.transformationController.value.entry(
      0,
      3,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(next, 0);
    expect(
      zoomController.transformationController.value.entry(0, 3),
      before - 48,
    );
  });

  testWidgets('the explicit Next button still selects while zoomed', (
    WidgetTester tester,
  ) async {
    int next = 0;
    final GalleryZoomController zoomController = GalleryZoomController();
    addTearDown(zoomController.dispose);
    await _pumpViewer(
      tester,
      zoomController: zoomController,
      disableAnimations: true,
      itemCount: 2,
      onNext: () => next++,
    );
    await tester.tap(find.byKey(const Key('immersive-viewer-zoom')));
    await tester.pump();
    final double before = zoomController.transformationController.value.entry(
      0,
      3,
    );

    tester
        .widget<IconButton>(
          find.byKey(const Key('immersive-viewer-next')),
        )
        .onPressed!();
    await tester.pump();

    // A labelled button names a wallpaper; an arrow key only names a
    // direction, and a direction is ambiguous exactly when zoomed. So the same
    // gesture the arrow key pans with, this selects with — deliberately.
    expect(next, 1);
    expect(zoomController.transformationController.value.entry(0, 3), before);
  });

  testWidgets('enters immersive mode and restores before close', (
    WidgetTester tester,
  ) async {
    final FakeImmersiveSystemUi systemUi = FakeImmersiveSystemUi();
    await _pumpViewer(
      tester,
      systemUi: systemUi,
      onClose: () async => systemUi.events.add('close'),
    );

    expect(systemUi.events, <String>['enter']);
    await tester.tap(find.byKey(const Key('immersive-viewer-close')));
    await tester.pump();

    expect(systemUi.events, <String>['enter', 'restore', 'close']);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(systemUi.restoreCalls, 1);
  });

  testWidgets('opens details only after restoring system chrome', (
    WidgetTester tester,
  ) async {
    final FakeImmersiveSystemUi systemUi = FakeImmersiveSystemUi();
    await _pumpViewer(
      tester,
      systemUi: systemUi,
      onOpenDetails: () async => systemUi.events.add('details'),
    );

    expect(
      find.byKey(const Key('immersive-viewer-open-details')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('immersive-viewer-open-details')));
    await tester.pump();

    expect(systemUi.events, <String>['enter', 'restore', 'details']);
  });

  testWidgets('disposal also restores normal system chrome', (
    WidgetTester tester,
  ) async {
    final FakeImmersiveSystemUi systemUi = FakeImmersiveSystemUi();
    await _pumpViewer(tester, systemUi: systemUi);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(systemUi.enterCalls, 1);
    expect(systemUi.restoreCalls, 1);
  });

  testWidgets('keeps the image and recomputes contain geometry on rotation', (
    WidgetTester tester,
  ) async {
    final FakeGalleryImageSource source = FakeGalleryImageSource();
    await _pumpViewer(
      tester,
      source: source,
      aspectRatio: 9 / 16,
      viewportSize: const Size(300, 600),
    );
    Size frame = tester.getSize(find.byKey(GalleryViewport.imageFrameKey));
    expect(frame, const Size(300, 533.3333333333334));

    await _pumpViewer(
      tester,
      source: source,
      aspectRatio: 9 / 16,
      viewportSize: const Size(600, 300),
    );
    frame = tester.getSize(find.byKey(GalleryViewport.imageFrameKey));
    expect(frame, const Size(168.75, 300));
    expect(find.bySemanticsLabel('Selected wallpaper'), findsOneWidget);
    expect(source.buildCalls, greaterThanOrEqualTo(2));
  });

  /// The chrome must resolve its scrim from the scheme, not from a constant.
  /// It used to hardcode `Colors.black45` in six places, which is why the
  /// viewer stayed a black void while the Detail screen it opens from paints
  /// itself in the wallpaper's own colour. Two themes, two scrims — a revert
  /// to constants fails here.
  testWidgets('the chrome is painted by the theme, not by a constant', (
    WidgetTester tester,
  ) async {
    final ColorScheme warm = ColorScheme.fromSeed(
      seedColor: const Color(0xFFCC5500),
      brightness: Brightness.dark,
    );
    final ColorScheme cool = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0055CC),
      brightness: Brightness.dark,
    );

    await _pumpViewer(tester, theme: ThemeData(colorScheme: warm));
    final Set<Color?> warmScrims = _chromeScrims(tester);

    await _pumpViewer(tester, theme: ThemeData(colorScheme: cool));
    // MaterialApp crossfades between two themes, so the frame straight after
    // the pump is still mostly the warm one — measured here, not assumed.
    await tester.pump(const Duration(milliseconds: 500));
    final Set<Color?> coolScrims = _chromeScrims(tester);

    expect(warmScrims, contains(ImmersiveChromePalette.fromScheme(warm).scrim));
    expect(coolScrims, contains(ImmersiveChromePalette.fromScheme(cool).scrim));
    expect(warmScrims.intersection(coolScrims), isEmpty);
    expect(warmScrims, isNot(contains(Colors.black45)));
  });

  testWidgets('the chrome fades on its own once nothing is touching it', (
    WidgetTester tester,
  ) async {
    await _pumpViewer(tester, disableAnimations: true);

    // It opens visible on purpose: the way out has to be shown before it goes.
    expect(_chromeOpacity(tester), 1);

    await tester.pump(const Duration(seconds: 4));

    expect(_chromeOpacity(tester), 0);
  });

  testWidgets('a touch restarts the countdown rather than being ignored', (
    WidgetTester tester,
  ) async {
    await _pumpViewer(tester, disableAnimations: true);

    await tester.pump(const Duration(seconds: 2));
    // Straight down and up on the canvas without travelling: a tap, which
    // toggles the chrome off and back on, is not what is being measured here.
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(GalleryViewport)),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(_chromeOpacity(tester), 1);

    await gesture.up();
    await tester.pump(const Duration(seconds: 4));

    expect(_chromeOpacity(tester), 0);
  });

  /// The fade is a sighted-touch affordance. Bringing the chrome back is a tap
  /// on the canvas — a gesture, and a gesture is exactly what a switch or
  /// screen-reader user does not have — so a clock that takes the controls
  /// away would take them away for good.
  testWidgets('the chrome never fades while assistive navigation is on', (
    WidgetTester tester,
  ) async {
    await _pumpViewer(
      tester,
      disableAnimations: true,
      accessibleNavigation: true,
    );

    await tester.pump(const Duration(seconds: 10));

    expect(_chromeOpacity(tester), 1);
  });
}

Future<void> _pumpViewer(
  WidgetTester tester, {
  GalleryZoomController? zoomController,
  FakeImmersiveSystemUi? systemUi,
  FakeGalleryImageSource? source,
  Future<void> Function()? onClose,
  Future<void> Function()? onOpenDetails,
  bool disableAnimations = false,
  double aspectRatio = 16 / 9,
  Size viewportSize = const Size(800, 600),
  int position = 1,
  int itemCount = 1,
  VoidCallback? onPrevious,
  VoidCallback? onNext,
  ThemeData? theme,
  bool accessibleNavigation = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: viewportSize,
          disableAnimations: disableAnimations,
          accessibleNavigation: accessibleNavigation,
        ),
        child: Center(
          child: SizedBox.fromSize(
            size: viewportSize,
            child: ImmersiveGalleryViewer(
              aspectRatio: aspectRatio,
              semanticsLabel: 'Selected wallpaper',
              source: source ?? FakeGalleryImageSource(),
              zoomController: zoomController,
              systemUi: systemUi ?? FakeImmersiveSystemUi(),
              onClose: onClose ?? () async {},
              onOpenDetails: onOpenDetails,
              position: position,
              itemCount: itemCount,
              onPrevious: onPrevious,
              onNext: onNext,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

final class FakeGalleryImageSource implements GalleryImageSource {
  int buildCalls = 0;

  @override
  Widget build(BuildContext context, GalleryImageRequest request) {
    buildCalls += 1;
    return const ColoredBox(color: Colors.blue);
  }
}

Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump(kDoubleTapMinTime);
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump(kDoubleTapTimeout);
}

/// Every scrim the chrome is currently painting, from both the position label
/// and the action bar.
Set<Color?> _chromeScrims(WidgetTester tester) {
  return tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: find.byKey(const Key('immersive-viewer-chrome')),
          matching: find.byType(DecoratedBox),
        ),
      )
      .map((DecoratedBox box) => (box.decoration as BoxDecoration).color)
      .whereType<Color>()
      .toSet();
}

/// The chrome's current opacity, which is how visible it actually is — the
/// widget stays mounted either way.
double _chromeOpacity(WidgetTester tester) {
  return tester
      .widget<AnimatedOpacity>(find.byKey(const Key('immersive-viewer-chrome')))
      .opacity;
}
