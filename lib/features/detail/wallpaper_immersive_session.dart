import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/copy_wallpaper_action.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/gallery_zoom_controller.dart';
import 'package:tela/core/ui/immersive_gallery_viewer.dart';
import 'package:tela/core/ui/immersive_system_ui.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/browse/wallpaper_quick_sheet.dart';
import 'package:tela/features/detail/progressive_wallpaper_preview.dart';
import 'package:tela/features/favorites/favorites_providers.dart';

/// Keeps one immersive route mounted while the gallery selection changes.
///
/// Carries favorite, download and Set wallpaper in its bottom bar. Without
/// them this was the only viewer in the app you could not act from — you were
/// looking at a wallpaper full-bleed, deciding whether you wanted it, and had
/// to close out to the Detail screen to say so (owner, 2026-07-19).
class WallpaperImmersiveSession extends ConsumerStatefulWidget {
  /// Creates the fullscreen surface for [gallery].
  const WallpaperImmersiveSession({
    required this.gallery,
    required this.systemUi,
    required this.onClose,
    super.key,
  });

  /// The same selection controller used by the surrounding Detail screen.
  final GallerySessionController<Wallpaper> gallery;

  /// System chrome lifecycle for this immersive route.
  final ImmersiveSystemUi systemUi;

  /// Closes the immersive route after chrome restoration.
  final Future<void> Function() onClose;

  @override
  ConsumerState<WallpaperImmersiveSession> createState() =>
      _WallpaperImmersiveSessionState();
}

class _WallpaperImmersiveSessionState
    extends ConsumerState<WallpaperImmersiveSession> {
  late final GalleryZoomController _zoomController;
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _zoomController = GalleryZoomController();
    _selectedIndex = widget.gallery.selectedIndex;
    widget.gallery.addListener(_galleryChanged);
  }

  @override
  void didUpdateWidget(WallpaperImmersiveSession oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gallery == widget.gallery) return;
    oldWidget.gallery.removeListener(_galleryChanged);
    widget.gallery.addListener(_galleryChanged);
    _selectedIndex = widget.gallery.selectedIndex;
    _zoomController.reset();
  }

  /// Rebuilds on any session change, but resets zoom only when the selected
  /// image actually changes — an appended page must not fling the current
  /// image back to fitted scale mid-view.
  void _galleryChanged() {
    if (widget.gallery.selectedIndex != _selectedIndex) {
      _selectedIndex = widget.gallery.selectedIndex;
      _zoomController.reset();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.gallery.removeListener(_galleryChanged);
    _zoomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final GallerySessionController<Wallpaper> gallery = widget.gallery;
    final Wallpaper wallpaper = gallery.selectedItem;
    return ImmersiveGalleryViewer(
      aspectRatio: wallpaper.resolution.width / wallpaper.resolution.height,
      semanticsLabel: l10n.detailPreviewLabel(wallpaper.id),
      source: ProgressiveWallpaperPreview.sourceFor(wallpaper),
      position: gallery.selectedIndex + 1,
      itemCount: gallery.items.length,
      onPrevious: gallery.canSelectPrevious ? gallery.selectPrevious : null,
      onNext: gallery.canSelectNext ? gallery.selectNext : null,
      onHold: _holdToCopy(wallpaper),
      zoomController: _zoomController,
      systemUi: widget.systemUi,
      onClose: widget.onClose,
      onOpenDetails: widget.onClose,
      barActions: _barActions(l10n, wallpaper),
    );
  }

  /// Holding the image copies it — the same gesture Detail's preview carries,
  /// on the surface where the wallpaper is actually being examined, and at
  /// every purity (see `shareOptionsFor`). An explicit copy is marked sensitive
  /// on the way out, which is what keeps its thumbnail out of the system's
  /// clipboard preview.
  VoidCallback _holdToCopy(Wallpaper wallpaper) {
    return () => unawaited(
      copyWallpaperToClipboard(
        context: context,
        ref: ref,
        wallpaper: wallpaper,
      ),
    );
  }

  /// Favorite, download and set — the three wallpaper mutations the quick
  /// sheet offers. Open details is a top-row viewer action because it changes
  /// screens rather than changing the wallpaper.
  ///
  /// Each one runs through [runWallpaperQuickAction] rather than growing its
  /// own copy: the target chooser, the snackbars and the `refreshFavorites` /
  /// `refreshDownloads` invalidations are all decided there, and two
  /// implementations of "download this wallpaper" would drift.
  List<Widget> _barActions(AppLocalizations l10n, Wallpaper wallpaper) {
    // An unresolved read draws the empty heart rather than a spinner, for the
    // reason `FavoriteButton` gives: the answer is one local SQLite round trip
    // away, and a flicker of progress reads worse than an outline that fills.
    final bool isFavorite =
        ref.watch(isFavoriteProvider(wallpaper.ref)).value ?? false;
    return <Widget>[
      _action(
        key: const Key('immersive-viewer-favorite'),
        icon: isFavorite ? Icons.favorite : Icons.favorite_border,
        label: isFavorite ? l10n.favoriteRemove : l10n.favoriteAdd,
        action: WallpaperQuickAction.favorite,
        wallpaper: wallpaper,
      ),
      _action(
        key: const Key('immersive-viewer-download'),
        icon: Icons.download_outlined,
        label: l10n.detailDownload,
        action: WallpaperQuickAction.download,
        wallpaper: wallpaper,
      ),
      _action(
        key: const Key('immersive-viewer-set'),
        icon: Icons.wallpaper_outlined,
        label: l10n.detailSetWallpaper,
        action: WallpaperQuickAction.setWallpaper,
        wallpaper: wallpaper,
      ),
    ];
  }

  Widget _action({
    required Key key,
    required IconData icon,
    required String label,
    required WallpaperQuickAction action,
    required Wallpaper wallpaper,
  }) {
    return IconButton(
      key: key,
      // The Icon carries the accessible name; see the controls' note on why
      // a tooltip is not a dependable source for one.
      icon: Icon(icon, semanticLabel: label),
      color: Colors.white,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      onPressed: () => unawaited(_run(action, wallpaper)),
    );
  }

  Future<void> _run(WallpaperQuickAction action, Wallpaper wallpaper) {
    return runWallpaperQuickAction(
      context: context,
      ref: ref,
      wallpaper: wallpaper,
      action: action,
      // Unreachable: the viewer owns its dedicated Open details control rather
      // than routing it through a wallpaper mutation.
      openDetail: () => throw StateError(
        'Open details is handled by the immersive viewer',
      ),
    );
  }
}
