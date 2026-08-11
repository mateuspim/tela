import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_route_transitions.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/immersive_system_ui.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
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
/// )
/// ```
class DetailPreviewPager extends StatefulWidget {
  /// Creates the pager over [gallery]'s shelf.
  const DetailPreviewPager({
    required this.gallery,
    required this.systemUi,
    super.key,
  });

  /// The shelf being paged. Its creator retains disposal ownership.
  final GallerySessionController<Wallpaper> gallery;

  /// The Android system-chrome seam the fullscreen viewer hides bars through.
  final ImmersiveSystemUi systemUi;

  @override
  State<DetailPreviewPager> createState() => _DetailPreviewPagerState();
}

class _DetailPreviewPagerState extends State<DetailPreviewPager> {
  late final PageController _pages;

  GallerySessionController<Wallpaper> get _gallery => widget.gallery;

  @override
  void initState() {
    super.initState();
    _pages = PageController(initialPage: _gallery.selectedIndex);
    _gallery.addListener(_selectionChanged);
  }

  /// Keeps the pager on the session's selection, whichever moved it.
  ///
  /// A swipe drives the session through [_onPageTurned]; anything else — the
  /// chevrons, or the fullscreen viewer paging the shared session while Detail
  /// sits behind it — moves the session first, and the pager is caught up here.
  /// The guard makes the two directions one loop, not two: a swipe leaves the
  /// pager already on the selection, so nothing is jumped back.
  void _selectionChanged() {
    if (!mounted) return;
    if (_pages.hasClients && _pages.page?.round() != _gallery.selectedIndex) {
      _pages.jumpToPage(_gallery.selectedIndex);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _gallery.removeListener(_selectionChanged);
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        PageView.builder(
          controller: _pages,
          onPageChanged: _onPageTurned,
          itemCount: _gallery.items.length,
          itemBuilder: (BuildContext context, int index) => _previewPage(index),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: IconButton.filledTonal(
            onPressed: _enterFullscreen,
            tooltip: AppLocalizations.of(context).detailEnterFullscreen,
            icon: const Icon(Icons.fullscreen),
          ),
        ),
        if (_gallery.canSelectPrevious)
          _pageChevron(
            key: const Key('detail-previous'),
            alignment: Alignment.centerLeft,
            icon: Icons.chevron_left,
            tooltip: AppLocalizations.of(context).galleryPrevious,
            onPressed: () => _turnTo(_gallery.selectedIndex - 1),
          ),
        if (_gallery.canSelectNext)
          _pageChevron(
            key: const Key('detail-next'),
            alignment: Alignment.centerRight,
            icon: Icons.chevron_right,
            tooltip: AppLocalizations.of(context).galleryNext,
            onPressed: () => _turnTo(_gallery.selectedIndex + 1),
          ),
      ],
    );
  }

  /// One page of the preview pager.
  ///
  /// Only the selected page carries the shared-element [Hero]: the grid flies
  /// one tile in, and a second Hero whose tag matches another grid tile would
  /// be the "multiple heroes" crash, so the neighbours the pager pre-builds
  /// stay heroless until they are the one on screen.
  Widget _previewPage(int index) {
    final Wallpaper wallpaper = _gallery.items[index];
    return ProgressiveWallpaperPreview(
      wallpaper: wallpaper,
      fillLetterbox: true,
      heroTag: index == _gallery.selectedIndex
          ? shelfHeroTag(_gallery.identity, wallpaper.ref.key, index)
          : null,
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
