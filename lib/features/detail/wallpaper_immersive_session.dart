import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/gallery_zoom_controller.dart';
import 'package:tela/core/ui/immersive_gallery_viewer.dart';
import 'package:tela/core/ui/immersive_system_ui.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/detail/progressive_wallpaper_preview.dart';

/// Keeps one immersive route mounted while the gallery selection changes.
class WallpaperImmersiveSession extends StatefulWidget {
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
  State<WallpaperImmersiveSession> createState() =>
      _WallpaperImmersiveSessionState();
}

class _WallpaperImmersiveSessionState extends State<WallpaperImmersiveSession> {
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
      zoomController: _zoomController,
      systemUi: widget.systemUi,
      onClose: widget.onClose,
    );
  }
}
