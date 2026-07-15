import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_viewport.dart';
import 'package:tela/core/ui/gallery_zoom_controller.dart';
import 'package:tela/core/ui/immersive_gallery_controls.dart';
import 'package:tela/core/ui/immersive_system_ui.dart';

/// A reusable edge-to-edge gallery surface with zoom and transient chrome.
class ImmersiveGalleryViewer extends StatefulWidget {
  /// Creates an immersive viewer for one honest-aspect-ratio image.
  const ImmersiveGalleryViewer({
    required this.aspectRatio,
    required this.semanticsLabel,
    required this.source,
    required this.onClose,
    this.position = 1,
    this.itemCount = 1,
    this.onPrevious,
    this.onNext,
    this.zoomController,
    this.systemUi = const FlutterImmersiveSystemUi(),
    this.primaryAction,
    this.actions = const <Widget>[],
    this.statusOverlay,
    this.heroTag,
    super.key,
  }) : assert(aspectRatio > 0, 'aspectRatio must be positive'),
       assert(itemCount > 0, 'itemCount must be positive'),
       assert(position > 0 && position <= itemCount, 'position must be valid');

  /// The source width divided by its height.
  final double aspectRatio;

  /// The screen-reader description for the selected image.
  final String semanticsLabel;

  /// The pixels rendered by the shared [GalleryViewport].
  final GalleryImageSource source;

  /// Closes the surrounding fullscreen route after system chrome is restored.
  final Future<void> Function() onClose;

  /// One-based selected position exposed to sighted and assistive users.
  final int position;

  /// Number of already-loaded items reachable in this session.
  final int itemCount;

  /// Selects the previous item. Null at a true loaded boundary.
  final VoidCallback? onPrevious;

  /// Selects the next item. Null at a true loaded boundary.
  final VoidCallback? onNext;

  /// Optional externally owned zoom state, primarily for gallery sessions.
  final GalleryZoomController? zoomController;

  /// Injectable system-UI lifecycle used by Android and focused tests.
  final ImmersiveSystemUi systemUi;

  /// A feature's primary action, shown in the transient chrome above the
  /// navigation row. History passes its Set-wallpaper button here. The viewer
  /// does not know what it does — feature actions stay outside the surface.
  final Widget? primaryAction;

  /// Feature actions shown in the top control row, before the close button.
  /// History passes its overflow menu here. Fades with the rest of the chrome.
  final List<Widget> actions;

  /// A persistent status shown independent of chrome, at the top. History uses
  /// it for the "not on this device" badge so a missing file stays obvious even
  /// while the controls are hidden.
  final Widget? statusOverlay;

  /// Optional shared-element tag flying the shelf tile into the shown image.
  /// Scope it by shelf identity (see `shelfHeroTag`); null leaves it heroless.
  final Object? heroTag;

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
  int _pointerCount = 0;
  Offset? _swipeStart;
  Offset? _swipeLatest;

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
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _startSwipe,
      onPointerMove: _updateSwipe,
      onPointerUp: _finishSwipe,
      onPointerCancel: _cancelSwipe,
      child: Semantics(
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
          heroTag: widget.heroTag,
          transformationController: _zoomController.transformationController,
          onInteractionStart: _stopProgrammaticZoom,
          onTap: _toggleChrome,
          onDoubleTapDown: _rememberDoubleTap,
          onDoubleTap: _toggleDoubleTapZoom,
        ),
      ),
    );
  }

  void _startSwipe(PointerDownEvent event) {
    _pointerCount++;
    if (_pointerCount != 1 || _zoomController.isZoomed) {
      _swipeStart = null;
      return;
    }
    _swipeStart = event.localPosition;
    _swipeLatest = event.localPosition;
  }

  void _updateSwipe(PointerMoveEvent event) {
    if (_pointerCount == 1 && _swipeStart != null) {
      _swipeLatest = event.localPosition;
    }
  }

  void _finishSwipe(PointerUpEvent event) {
    final Offset? start = _swipeStart;
    final Offset end = _swipeLatest ?? event.localPosition;
    if (_pointerCount > 0) _pointerCount--;
    _swipeStart = null;
    _swipeLatest = null;
    if (_pointerCount != 0 || start == null || _zoomController.isZoomed) return;
    final Offset delta = end - start;
    if (delta.dx.abs() < 64 || delta.dx.abs() <= delta.dy.abs()) return;
    if (delta.dx < 0) {
      widget.onNext?.call();
    } else {
      widget.onPrevious?.call();
    }
  }

  void _cancelSwipe(PointerCancelEvent event) {
    if (_pointerCount > 0) _pointerCount--;
    _swipeStart = null;
    _swipeLatest = null;
  }

  void _handlePreviousInput() {
    if (_zoomController.isZoomed) {
      _zoomController.panBy(const Offset(48, 0));
      return;
    }
    widget.onPrevious?.call();
  }

  void _handleNextInput() {
    if (_zoomController.isZoomed) {
      _zoomController.panBy(const Offset(-48, 0));
      return;
    }
    widget.onNext?.call();
  }

  Widget _viewerChrome() {
    return ImmersiveGalleryControls(
      visible: _chromeVisible,
      duration: _chromeDuration(),
      zoomed: _zoomController.isZoomed,
      onToggleZoom: _toggleCenteredZoom,
      onClose: () => unawaited(_exitFullscreen()),
      position: widget.position,
      itemCount: widget.itemCount,
      onPrevious: widget.onPrevious,
      onNext: widget.onNext,
      primaryAction: widget.primaryAction,
      actions: widget.actions,
    );
  }

  Widget _statusOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        minimum: const EdgeInsets.only(top: 8),
        child: Align(child: widget.statusOverlay),
      ),
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
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowLeft):
              _handlePreviousInput,
          const SingleActivator(LogicalKeyboardKey.arrowRight):
              _handleNextInput,
        },
        child: Focus(
          autofocus: true,
          child: Material(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _imageCanvas(l10n),
                _viewerChrome(),
                if (widget.statusOverlay != null) _statusOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
