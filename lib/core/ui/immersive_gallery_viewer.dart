import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_viewport.dart';
import 'package:tela/core/ui/gallery_zoom_controller.dart';
import 'package:tela/core/ui/immersive_system_ui.dart';

/// A reusable edge-to-edge gallery surface with zoom and transient chrome.
class ImmersiveGalleryViewer extends StatefulWidget {
  /// Creates an immersive viewer for one honest-aspect-ratio image.
  const ImmersiveGalleryViewer({
    required this.aspectRatio,
    required this.semanticsLabel,
    required this.source,
    required this.onClose,
    this.zoomController,
    this.systemUi = const FlutterImmersiveSystemUi(),
    super.key,
  }) : assert(aspectRatio > 0, 'aspectRatio must be positive');

  /// The source width divided by its height.
  final double aspectRatio;

  /// The screen-reader description for the selected image.
  final String semanticsLabel;

  /// The pixels rendered by the shared [GalleryViewport].
  final GalleryImageSource source;

  /// Closes the surrounding fullscreen route after system chrome is restored.
  final Future<void> Function() onClose;

  /// Optional externally owned zoom state, primarily for gallery sessions.
  final GalleryZoomController? zoomController;

  /// Injectable system-UI lifecycle used by Android and focused tests.
  final ImmersiveSystemUi systemUi;

  @override
  State<ImmersiveGalleryViewer> createState() => _ImmersiveGalleryViewerState();
}

class _ImmersiveGalleryViewerState extends State<ImmersiveGalleryViewer>
    with SingleTickerProviderStateMixin {
  static const Duration _transitionDuration = Duration(milliseconds: 180);

  late GalleryZoomController _zoomController;
  late bool _ownsZoomController;
  late final AnimationController _zoomAnimationController;
  Matrix4Tween? _zoomTween;
  late final ImmersiveSystemUi _activeSystemUi;
  late final Future<void> _enterSystemUi;
  bool _chromeVisible = true;
  bool _systemUiRestored = false;
  bool _isExiting = false;
  bool _allowPop = false;
  Offset _doubleTapPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _adoptZoomController(widget.zoomController);
    _zoomController.addListener(_rebuildZoomChrome);
    _zoomAnimationController = AnimationController(
      vsync: this,
      duration: _transitionDuration,
    )..addListener(_applyZoomAnimation);
    _activeSystemUi = widget.systemUi;
    _enterSystemUi = _activeSystemUi.enterImmersive();
  }

  @override
  void didUpdateWidget(ImmersiveGalleryViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoomController == widget.zoomController) return;
    _zoomAnimationController.stop();
    _zoomTween = null;
    _zoomController.removeListener(_rebuildZoomChrome);
    if (_ownsZoomController) _zoomController.dispose();
    _adoptZoomController(widget.zoomController);
    _zoomController.addListener(_rebuildZoomChrome);
  }

  void _adoptZoomController(GalleryZoomController? controller) {
    _ownsZoomController = controller == null;
    _zoomController = controller ?? GalleryZoomController();
  }

  @override
  void dispose() {
    unawaited(_restoreSystemUi());
    _zoomAnimationController.dispose();
    _zoomController.removeListener(_rebuildZoomChrome);
    if (_ownsZoomController) _zoomController.dispose();
    super.dispose();
  }

  void _rebuildZoomChrome() {
    if (mounted) setState(() {});
  }

  void _applyZoomAnimation() {
    final Matrix4Tween? tween = _zoomTween;
    if (tween == null) return;
    _zoomController.transformationController.value = tween.evaluate(
      _zoomAnimationController,
    );
  }

  Future<void> _restoreSystemUi() async {
    if (_systemUiRestored) return;
    _systemUiRestored = true;
    await _enterSystemUi;
    await _activeSystemUi.restoreNormal();
  }

  Future<void> _exitFullscreen() async {
    if (_isExiting) return;
    _isExiting = true;
    await _restoreSystemUi();
    if (!mounted) return;
    setState(() => _allowPop = true);
    await widget.onClose();
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
  }

  void _rememberDoubleTap(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _toggleDoubleTapZoom() {
    _toggleZoomAt(_doubleTapPosition);
  }

  void _toggleCenteredZoom() {
    final Size viewport = MediaQuery.sizeOf(context);
    _toggleZoomAt(viewport.center(Offset.zero));
  }

  void _toggleZoomAt(Offset focalPoint) {
    final Matrix4 target = _zoomController.isZoomed
        ? Matrix4.identity()
        : _zoomController.zoomedMatrixAt(focalPoint);
    _animateZoomTo(target);
  }

  void _animateZoomTo(Matrix4 target) {
    _zoomAnimationController.stop();
    if (MediaQuery.disableAnimationsOf(context)) {
      _zoomController.transformationController.value = target;
      return;
    }
    _zoomTween = Matrix4Tween(
      begin: Matrix4.copy(_zoomController.transformationController.value),
      end: target,
    );
    unawaited(_zoomAnimationController.forward(from: 0));
  }

  void _stopProgrammaticZoom(ScaleStartDetails details) {
    _zoomAnimationController.stop();
  }

  Duration _chromeDuration() {
    return MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _transitionDuration;
  }

  Widget _imageCanvas(AppLocalizations l10n) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: _chromeVisible
          ? l10n.galleryHideControls
          : l10n.galleryShowControls,
      onTap: _toggleChrome,
      child: GalleryViewport(
        aspectRatio: widget.aspectRatio,
        semanticsLabel: widget.semanticsLabel,
        source: widget.source,
        transformationController: _zoomController.transformationController,
        onInteractionStart: _stopProgrammaticZoom,
        onTap: _toggleChrome,
        onDoubleTapDown: _rememberDoubleTap,
        onDoubleTap: _toggleDoubleTapZoom,
      ),
    );
  }

  Widget _viewerChrome() {
    return _ViewerChrome(
      visible: _chromeVisible,
      duration: _chromeDuration(),
      zoomed: _zoomController.isZoomed,
      onToggleZoom: _toggleCenteredZoom,
      onClose: () => unawaited(_exitFullscreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (bool didPop, void result) {
        if (!didPop) unawaited(_exitFullscreen());
      },
      child: Material(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _imageCanvas(l10n),
            _viewerChrome(),
          ],
        ),
      ),
    );
  }
}

class _ViewerChrome extends StatelessWidget {
  const _ViewerChrome({
    required this.visible,
    required this.duration,
    required this.zoomed,
    required this.onToggleZoom,
    required this.onClose,
  });

  final bool visible;
  final Duration duration;
  final bool zoomed;
  final VoidCallback onToggleZoom;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedOpacity(
          key: const Key('immersive-viewer-chrome'),
          opacity: visible ? 1 : 0,
          duration: duration,
          child: SafeArea(
            minimum: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.topCenter,
              child: _controlRow(l10n),
            ),
          ),
        ),
      ),
    );
  }

  Widget _controlRow(AppLocalizations l10n) {
    return Row(
      children: <Widget>[
        _alignedControl(Alignment.centerLeft, _zoomButton(l10n)),
        const SizedBox(width: 12),
        _alignedControl(Alignment.centerRight, _closeButton(l10n)),
      ],
    );
  }

  Widget _alignedControl(Alignment alignment, Widget child) {
    return Expanded(
      child: Align(alignment: alignment, child: child),
    );
  }

  Widget _zoomButton(AppLocalizations l10n) {
    return FilledButton.tonalIcon(
      key: const Key('immersive-viewer-zoom'),
      onPressed: onToggleZoom,
      style: _buttonStyle(),
      icon: Icon(zoomed ? Icons.zoom_out_map : Icons.zoom_in),
      label: Text(zoomed ? l10n.galleryResetZoom : l10n.galleryZoomIn),
    );
  }

  Widget _closeButton(AppLocalizations l10n) {
    return FilledButton.icon(
      key: const Key('immersive-viewer-close'),
      onPressed: onClose,
      style: _buttonStyle(),
      icon: const Icon(Icons.close),
      label: Text(l10n.galleryClose),
    );
  }

  ButtonStyle _buttonStyle() {
    return FilledButton.styleFrom(minimumSize: const Size(48, 48));
  }
}
