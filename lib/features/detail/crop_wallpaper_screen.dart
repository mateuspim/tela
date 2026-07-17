import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_viewport.dart';
import 'package:tela/core/ui/wallpaper_target_sheet.dart';
import 'package:tela/domain/models/crop_region.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/features/detail/crop_controller.dart';
import 'package:tela/features/detail/progressive_wallpaper_preview.dart';

/// tela's own crop editor: frame a wallpaper against the screen, then set it.
///
/// The in-app path that keeps explicit pixels inside the app — the OEM editor
/// (`AdjustWallpaper`) is refused for them. Reached for every NSFW adjust, and
/// as the fallback when a device offers no OEM editor at all. Unlike that
/// hand-off, tela owns the apply here, so success is honestly reported.
class CropWallpaperScreen extends ConsumerStatefulWidget {
  /// Creates the crop editor for [wallpaper].
  const CropWallpaperScreen({required this.wallpaper, super.key});

  /// The wallpaper whose full-resolution image is being framed.
  final Wallpaper wallpaper;

  /// Stable hook for the Set-wallpaper action in tests.
  static const Key setButtonKey = Key('crop-set-wallpaper');

  /// Stable hook for the decoded image layer, whose layout size must stay
  /// constant under zoom (the transform is paint-only).
  static const Key imageLayerKey = Key('crop-image-layer');

  @override
  ConsumerState<CropWallpaperScreen> createState() =>
      _CropWallpaperScreenState();
}

class _CropWallpaperScreenState extends ConsumerState<CropWallpaperScreen> {
  late final GalleryImageSource _source = ProgressiveWallpaperPreview.sourceFor(
    widget.wallpaper,
  );
  late final Size _imageSize = Size(
    widget.wallpaper.resolution.width.toDouble(),
    widget.wallpaper.resolution.height.toDouble(),
  );

  CropController? _controller;
  Size _window = Size.zero;
  bool _isApplying = false;

  Offset _startFocal = Offset.zero;
  double _startScale = 1;
  Offset _startOffset = Offset.zero;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Rebuilds the controller when the frame first appears or its size changes,
  /// so a rotation reframes rather than driving a stale window's maths.
  void _syncController(Size window) {
    if (_controller != null && _window == window) return;
    _controller?.dispose();
    _controller = CropController(image: _imageSize, window: window);
    _window = window;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startFocal = details.localFocalPoint;
    _startScale = _controller!.scale;
    _startOffset = _controller!.offset;
  }

  /// Anchors the source point under the initial focal so pinch and pan both
  /// track the fingers. Derived in the plan; see [CropController] for clamping.
  void _onScaleUpdate(ScaleUpdateDetails details) {
    final CropController controller = _controller!;
    final double newScale = controller.clampScale(_startScale * details.scale);
    final Offset anchor = (_startFocal - _startOffset) / _startScale;
    final Offset newOffset = details.localFocalPoint - anchor * newScale;
    controller.update(scale: newScale, offset: newOffset);
  }

  Future<void> _setWallpaper() async {
    final WallpaperTarget? target = await chooseWallpaperTarget(context);
    if (target == null || !mounted) return;
    await _apply(target);
  }

  Future<void> _apply(WallpaperTarget target) async {
    setState(() => _isApplying = true);
    final CropRegion region = _controller!.region();
    try {
      await ref.read(applyCroppedWallpaperProvider)(
        widget.wallpaper,
        region,
        target,
      );
      if (!mounted) return;
      _showResult(AppLocalizations.of(context).detailApplySuccess);
      Navigator.of(context).pop();
    } on WallpaperApplyFailure {
      if (mounted) _showResult(AppLocalizations.of(context).detailApplyFailure);
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  void _showResult(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.detailCropTitle)),
      backgroundColor: Colors.black,
      body: Column(
        children: <Widget>[
          Expanded(child: _cropArea(context)),
          _bottomBar(l10n),
        ],
      ),
    );
  }

  Widget _cropArea(BuildContext context) {
    final double aspect = _screenAspect(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size window = containedImageSize(
          viewportSize: constraints.biggest,
          aspectRatio: aspect,
        );
        if (window.isEmpty) return const SizedBox.expand();
        _syncController(window);
        return Center(child: _frame(context, window));
      },
    );
  }

  double _screenAspect(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    if (screen.isEmpty) return _imageSize.width / _imageSize.height;
    return screen.width / screen.height;
  }

  Widget _frame(BuildContext context, Size window) {
    final CropController controller = _controller!;
    final double baseScale = controller.minScale;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        child: ClipRect(
          child: SizedBox.fromSize(
            size: window,
            child: AnimatedBuilder(
              animation: controller,
              // The image is decoded once, at cover scale, and passed as the
              // stable [child]. Zoom and pan are a paint-time Transform on top:
              // resizing the decoded widget per frame re-decoded it, which
              // flashed the black placeholder on every pinch.
              builder: (BuildContext context, Widget? child) => Transform(
                alignment: Alignment.topLeft,
                transform: Matrix4.identity()
                  ..translateByDouble(
                    controller.offset.dx,
                    controller.offset.dy,
                    0,
                    1,
                  )
                  ..scaleByDouble(
                    controller.scale / baseScale,
                    controller.scale / baseScale,
                    1,
                    1,
                  ),
                child: child,
              ),
              child: _imageLayer(context, baseScale),
            ),
          ),
        ),
      ),
    );
  }

  /// The image sized to its cover-scale display, free of the window's
  /// constraints so the Transform can place and scale it. Built once per frame
  /// (not per zoom tick) and at a fixed size, so it decodes only once.
  Widget _imageLayer(BuildContext context, double baseScale) {
    final Size base = _imageSize * baseScale;
    return OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: 0,
      maxWidth: double.infinity,
      minHeight: 0,
      maxHeight: double.infinity,
      child: SizedBox.fromSize(
        key: CropWallpaperScreen.imageLayerKey,
        size: base,
        child: _source.build(
          context,
          GalleryImageRequest(
            logicalSize: base,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(AppLocalizations l10n) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          TextButton.icon(
            onPressed: _isApplying ? null : () => _controller?.reset(),
            icon: const Icon(Icons.restart_alt),
            label: Text(l10n.detailCropReset),
          ),
          const Spacer(),
          FilledButton.icon(
            key: CropWallpaperScreen.setButtonKey,
            onPressed: _isApplying ? null : _setWallpaper,
            icon: _isApplying
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wallpaper_outlined),
            label: Text(l10n.detailSetWallpaper),
          ),
        ],
      ),
    );
  }
}
