import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_route_transitions.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/gallery_zoom_animator.dart';
import 'package:tela/core/ui/gallery_zoom_controller.dart';
import 'package:tela/core/ui/immersive_chrome_palette.dart';
import 'package:tela/core/ui/immersive_system_ui.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
import 'package:tela/core/ui/shelf_swipe.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/detail/progressive_wallpaper_preview.dart';
import 'package:tela/features/detail/wallpaper_immersive_session.dart';

/// The wallpaper, swipeable across the whole shelf without leaving Detail.
///
/// A [PageView] over the same session the fullscreen viewer pages, so a swipe
/// here moves the selection and the metadata, actions, and Set button below all
/// follow. Chevrons offer the same step for a thumb that would rather tap, each
/// shown only while there is a loaded neighbour to reach.
///
/// It owns the [PageController] because it is the only thing that has one to
/// keep in step; the screen around it listens to the same [gallery] for its own
/// reasons and neither has to know about the other.
///
/// ```dart
/// DetailPreviewPager(
///   gallery: session,
///   systemUi: const FlutterImmersiveSystemUi(),
///   onHoldImage: (Wallpaper wallpaper) => copy(wallpaper),
/// )
/// ```
class DetailPreviewPager extends StatefulWidget {
  /// Creates the pager over [gallery]'s shelf.
  const DetailPreviewPager({
    required this.gallery,
    required this.systemUi,
    this.onHoldImage,
    super.key,
  });

  /// The shelf being paged. Its creator retains disposal ownership.
  final GallerySessionController<Wallpaper> gallery;

  /// The Android system-chrome seam the fullscreen viewer hides bars through.
  final ImmersiveSystemUi systemUi;

  /// Called when a finger rests on the wallpaper on screen, conventionally to
  /// copy it. Null leaves the hold unarmed.
  ///
  /// Armed at every purity: a clipboard copy is offered for explicit wallpapers
  /// too, by the owner's decision — `shareOptionsFor` carries the reasoning and
  /// what it costs. Withholding it here would have been the third place the
  /// same rule was spelled out, and the first to disagree with the other two.
  final void Function(Wallpaper wallpaper)? onHoldImage;

  @override
  State<DetailPreviewPager> createState() => _DetailPreviewPagerState();
}

class _DetailPreviewPagerState extends State<DetailPreviewPager>
    with SingleTickerProviderStateMixin {
  late final PageController _pages;
  late final GalleryZoomController _zoom;
  late final GalleryZoomAnimator _zoomAnimator;
  late int _selectedIndex;

  GallerySessionController<Wallpaper> get _gallery => widget.gallery;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _gallery.selectedIndex;
    _pages = PageController(initialPage: _selectedIndex);
    _zoom = GalleryZoomController()..addListener(_zoomChanged);
    _zoomAnimator = GalleryZoomAnimator(vsync: this, zoom: _zoom);
    _gallery.addListener(_selectionChanged);
  }

  /// Keeps the pager on the session's selection, whichever moved it.
  ///
  /// A swipe drives the session through [_onPageTurned]; anything else — the
  /// chevrons, or the fullscreen viewer paging the shared session while Detail
  /// sits behind it — moves the session first, and the pager is caught up here.
  /// The guard makes the two directions one loop, not two: a swipe leaves the
  /// pager already on the selection, so nothing is jumped back.
  ///
  /// Zoom is reset only when the *selected image* changes, matching
  /// `WallpaperImmersiveSession`: a page appended to the shelf notifies too,
  /// and it must not fling the examined wallpaper back to fitted scale.
  void _selectionChanged() {
    if (!mounted) return;
    if (_gallery.selectedIndex != _selectedIndex) {
      _selectedIndex = _gallery.selectedIndex;
      // Before the reset, not after: a double-tap transition still in flight
      // would keep writing its tween into the freshly fitted controller and
      // land the *new* wallpaper at the old one's zoom.
      _zoomAnimator.stop();
      _zoom.reset();
    }
    if (_pages.hasClients && _pages.page?.round() != _selectedIndex) {
      _pages.jumpToPage(_selectedIndex);
    }
    setState(() {});
  }

  /// Rebuilds when zoom crosses the fitted/zoomed line, so [ShelfSwipe] stops
  /// offering to turn the page across a magnified image.
  void _zoomChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _gallery.removeListener(_selectionChanged);
    _zoomAnimator.dispose();
    _zoom
      ..removeListener(_zoomChanged)
      ..dispose();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _pinchablePager(),
        Positioned(
          // Cleared of whatever sits above the preview, because on the phone
          // layout that is a *floating* app bar and this button would land
          // underneath its actions — a tap on fullscreen opening the share
          // sheet instead. `Scaffold` folds the bar's height into the body's
          // own `MediaQuery.padding.top` when it extends behind it (see the
          // A2 aside in HANDOFF), so reading that padding is correct in both
          // layouts and double-counts in neither: the wide pane, whose bar
          // reserves its own space, reports zero here.
          top: 12 + MediaQuery.paddingOf(context).top,
          right: 12,
          // Sized and painted like the chrome it opens into, rather than as a
          // default tonal button: it sits over an arbitrary wallpaper, so it
          // needs the scrim its neighbours in the viewer get, and 48dp is the
          // target size the viewer's own controls are already held to.
          child: IconButton.filledTonal(
            onPressed: _enterFullscreen,
            tooltip: l10n.detailEnterFullscreen,
            style: IconButton.styleFrom(
              backgroundColor: ImmersiveChromePalette.of(context).scrim,
              foregroundColor: ImmersiveChromePalette.of(context).ink,
            ),
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            icon: const Icon(Icons.fullscreen),
          ),
        ),
        if (_gallery.canSelectPrevious)
          _pageChevron(
            key: const Key('detail-previous'),
            alignment: Alignment.centerLeft,
            icon: Icons.chevron_left,
            tooltip: l10n.galleryPrevious,
            onPressed: () => _turnTo(_selectedIndex - 1),
          ),
        if (_gallery.canSelectNext)
          _pageChevron(
            key: const Key('detail-next'),
            alignment: Alignment.centerRight,
            icon: Icons.chevron_right,
            tooltip: l10n.galleryNext,
            onPressed: () => _turnTo(_selectedIndex + 1),
          ),
      ],
    );
  }

  /// The pager, with the pinch taken back off it.
  ///
  /// The [PageView] is deliberately unscrollable and the swipe comes from
  /// [ShelfSwipe] instead. A [Scrollable] whose physics accept a user offset
  /// installs a horizontal drag recognizer, and that recognizer is the whole
  /// bug: it wins the arena off the first finger and the pinch never happens.
  /// Withholding physics only while a second finger is down does *not* fix it —
  /// measured — because by then the drag has already won and the scale
  /// recognizer has already been rejected for that pointer. The recognizer has
  /// to not exist. [ShelfSwipe] explains the arena in full.
  ///
  /// What is lost is the page tracking the finger mid-drag; what is kept is the
  /// animated turn, the pre-built neighbours, and a pinch that works every
  /// time. Fullscreen has paged exactly this way all along.
  Widget _pinchablePager() {
    return ShelfSwipe(
      isZoomed: _zoom.isZoomed,
      onPrevious: _gallery.canSelectPrevious
          ? () => _turnTo(_selectedIndex - 1)
          : null,
      onNext: _gallery.canSelectNext ? () => _turnTo(_selectedIndex + 1) : null,
      onHold: _holdSelected(),
      child: PageView.builder(
        controller: _pages,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: _onPageTurned,
        itemCount: _gallery.items.length,
        itemBuilder: (BuildContext context, int index) => _previewPage(index),
      ),
    );
  }

  /// One page of the preview pager.
  ///
  /// Only the selected page carries the shared-element [Hero]: the grid flies
  /// one tile in, and a second Hero whose tag matches another grid tile would
  /// be the "multiple heroes" crash, so the neighbours the pager pre-builds
  /// stay heroless until they are the one on screen.
  ///
  /// The zoom controller and the gestures that write to it are withheld from
  /// the neighbours for the same shape of reason: shared, an off-screen page
  /// would sit pre-zoomed under the swipe, and the pager builds neighbours
  /// before they are ever seen.
  Widget _previewPage(int index) {
    if (index != _selectedIndex) {
      return ProgressiveWallpaperPreview(
        wallpaper: _gallery.items[index],
        fillLetterbox: true,
      );
    }
    return _zoomablePage(index);
  }

  /// The page on screen: the only one holding zoom state, and so the only one
  /// that can be pinched, double-tapped, or panned.
  Widget _zoomablePage(int index) {
    final Wallpaper wallpaper = _gallery.items[index];
    return ProgressiveWallpaperPreview(
      wallpaper: wallpaper,
      fillLetterbox: true,
      transformationController: _zoom.transformationController,
      onInteractionStart: _zoomAnimator.stopForInteraction,
      onDoubleTapDown: _zoomAnimator.rememberDoubleTap,
      onDoubleTap: _toggleDoubleTapZoom,
      // The whole picture is the way into fullscreen, because the ⛶ alone was
      // hard to find and hard to hit (owner, 2026-08-17). The button stays: a
      // tap on an image is invisible to a screen reader, so it is never the
      // only route in — the same rule the hold-to-copy gesture follows.
      onTap: _enterFullscreen,
      heroTag: shelfHeroTag(_gallery.identity, wallpaper.ref.key, index),
    );
  }

  /// The hold, bound to the wallpaper on screen rather than to the pager, so a
  /// hold after a swipe copies what is actually being looked at.
  VoidCallback? _holdSelected() {
    final void Function(Wallpaper)? hold = widget.onHoldImage;
    if (hold == null) return null;
    final Wallpaper wallpaper = _gallery.items[_selectedIndex];
    return () => hold(wallpaper);
  }

  /// Double tap toggles between fitted and magnified around the tapped point —
  /// the gesture fullscreen has always had, and the last thing Detail's own
  /// zoom was missing once the pinch was won back from the pager.
  void _toggleDoubleTapZoom() {
    _zoomAnimator.toggleDoubleTapZoom(
      animate: !MediaQuery.disableAnimationsOf(context),
    );
  }

  Widget _pageChevron({
    required Key key,
    required Alignment alignment,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: IconButton.filledTonal(
          key: key,
          onPressed: onPressed,
          tooltip: tooltip,
          icon: Icon(icon),
        ),
      ),
    );
  }

  /// A swipe (or a chevron's animation) landed on [index]: move the session,
  /// which reselect-ignores a no-op and rebinds everything else.
  void _onPageTurned(int index) => _gallery.select(index);

  /// Steps the pager to [index], animating unless the platform asked not to —
  /// where a jump keeps the step instant and testable.
  void _turnTo(int index) {
    if (index < 0 || index >= _gallery.items.length) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(index);
      return;
    }
    unawaited(
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _enterFullscreen() {
    unawaited(Navigator.of(context).push<void>(_fullscreenRoute(context)));
  }

  PageRoute<void> _fullscreenRoute(BuildContext context) {
    final Duration duration = galleryTransitionDuration(context);
    return PageRouteBuilder<void>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) => _fullscreenSurface(context),
      transitionsBuilder: _fadeFullscreenRoute,
    );
  }

  Widget _fullscreenSurface(BuildContext routeContext) {
    return WallpaperImmersiveSession(
      gallery: _gallery,
      systemUi: widget.systemUi,
      onClose: () async => Navigator.of(routeContext).pop(),
    );
  }

  Widget _fadeFullscreenRoute(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }
}
