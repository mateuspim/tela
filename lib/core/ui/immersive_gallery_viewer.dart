import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_viewport.dart';
import 'package:tela/core/ui/gallery_zoom_animator.dart';
import 'package:tela/core/ui/gallery_zoom_controller.dart';
import 'package:tela/core/ui/immersive_gallery_controls.dart';
import 'package:tela/core/ui/immersive_system_ui.dart';
import 'package:tela/core/ui/shelf_swipe.dart';

/// A reusable edge-to-edge gallery surface with zoom and transient chrome.
class ImmersiveGalleryViewer extends StatefulWidget {
  /// Creates an immersive viewer for one honest-aspect-ratio image.
  const ImmersiveGalleryViewer({
    required this.aspectRatio,
    required this.semanticsLabel,
    required this.source,
    required this.onClose,
    this.onOpenDetails,
    this.position = 1,
    this.itemCount = 1,
    this.onPrevious,
    this.onNext,
    this.onHold,
    this.zoomController,
    this.systemUi = const FlutterImmersiveSystemUi(),
    this.barActions = const <Widget>[],
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

  /// Opens the selected image's Detail screen after system chrome is restored.
  ///
  /// Null for local-only images that cannot be reconstructed as a wallpaper.
  final Future<void> Function()? onOpenDetails;

  /// One-based selected position exposed to sighted and assistive users.
  final int position;

  /// Number of already-loaded items reachable in this session.
  final int itemCount;

  /// Selects the previous item. Null at a true loaded boundary.
  final VoidCallback? onPrevious;

  /// Selects the next item. Null at a true loaded boundary.
  final VoidCallback? onNext;

  /// Called when a finger rests on the fitted image, conventionally to copy it
  /// (see [ShelfSwipe.onHold]). Null leaves the gesture unarmed, which is what
  /// every surface holding images that may not leave the device passes — the
  /// private library above all.
  final VoidCallback? onHold;

  /// Optional externally owned zoom state, primarily for gallery sessions.
  final GalleryZoomController? zoomController;

  /// Injectable system-UI lifecycle used by Android and focused tests.
  final ImmersiveSystemUi systemUi;

  /// What this surface lets you do to the wallpaper on screen, seated in the
  /// bottom bar between the paging arrows. Browse passes favorite and download,
  /// History and the private library pass Set wallpaper. The viewer does not
  /// know what any of them do — feature actions stay outside the surface.
  final List<Widget> barActions;

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
  late final GalleryZoomAnimator _zoomAnimator;
  late final ImmersiveSystemUi _activeSystemUi;
  late final Future<void> _enterSystemUi;
  bool _chromeVisible = true;
  bool _systemUiRestored = false;
  bool _isExiting = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _adoptZoomController(widget.zoomController);
    _zoomController.addListener(_rebuildZoomChrome);
    // No duration passed: the zoom transition's length is the animator's to
    // define, so both surfaces offering the gesture move at the same speed.
    // `_transitionDuration` here is the chrome's fade, which happens to match.
    _zoomAnimator = GalleryZoomAnimator(vsync: this, zoom: _zoomController);
    _activeSystemUi = widget.systemUi;
    _enterSystemUi = _activeSystemUi.enterImmersive();
  }

  @override
  void didUpdateWidget(ImmersiveGalleryViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoomController == widget.zoomController) return;
    _zoomController.removeListener(_rebuildZoomChrome);
    if (_ownsZoomController) _zoomController.dispose();
    _adoptZoomController(widget.zoomController);
    _zoomController.addListener(_rebuildZoomChrome);
    _zoomAnimator.retarget(_zoomController);
  }

  void _adoptZoomController(GalleryZoomController? controller) {
    _ownsZoomController = controller == null;
    _zoomController = controller ?? GalleryZoomController();
  }

  @override
  void dispose() {
    unawaited(_restoreSystemUi());
    _zoomAnimator.dispose();
    _zoomController.removeListener(_rebuildZoomChrome);
    if (_ownsZoomController) _zoomController.dispose();
    super.dispose();
  }

  void _rebuildZoomChrome() {
    if (mounted) setState(() {});
  }

  Future<void> _restoreSystemUi() async {
    if (_systemUiRestored) return;
    _systemUiRestored = true;
    await _enterSystemUi;
    await _activeSystemUi.restoreNormal();
  }

  Future<void> _exitFullscreen() async {
    await _leaveFullscreen(widget.onClose);
  }

  Future<void> _openDetails() async {
    final Future<void> Function()? onOpenDetails = widget.onOpenDetails;
    if (onOpenDetails == null) return;
    await _leaveFullscreen(onOpenDetails);
  }

  Future<void> _leaveFullscreen(Future<void> Function() navigate) async {
    if (_isExiting) return;
    _isExiting = true;
    await _restoreSystemUi();
    if (!mounted) return;
    setState(() => _allowPop = true);
    await navigate();
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
  }

  /// Hides the chrome from the chrome's own button.
  ///
  /// The button goes away with everything else it sits among, so this is a
  /// one-way door and the canvas is the way back: tapping the image calls
  /// [_toggleChrome], and the canvas's semantics label announces exactly that
  /// (`galleryShowControls`) for a screen reader. Those two are what keep this
  /// from being a control that hides itself for good.
  void _hideChrome() {
    if (_chromeVisible) setState(() => _chromeVisible = false);
  }

  void _toggleDoubleTapZoom() {
    _zoomAnimator.toggleDoubleTapZoom(animate: _zoomAnimates());
  }

  void _toggleCenteredZoom() {
    final Size viewport = MediaQuery.sizeOf(context);
    _zoomAnimator.toggleZoomAt(
      viewport.center(Offset.zero),
      animate: _zoomAnimates(),
    );
  }

  bool _zoomAnimates() => !MediaQuery.disableAnimationsOf(context);

  Duration _chromeDuration() {
    return MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _transitionDuration;
  }

  Widget _imageCanvas(AppLocalizations l10n) {
    return ShelfSwipe(
      isZoomed: _zoomController.isZoomed,
      onPrevious: widget.onPrevious,
      onNext: widget.onNext,
      onHold: widget.onHold,
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
          onInteractionStart: _zoomAnimator.stopForInteraction,
          onTap: _toggleChrome,
          onDoubleTapDown: _zoomAnimator.rememberDoubleTap,
          onDoubleTap: _toggleDoubleTapZoom,
        ),
      ),
    );
  }

  /// Handles a *directional* left — an arrow key or D-pad, where the user is
  /// steering within the image rather than naming a wallpaper.
  ///
  /// Zoomed, that intent reads as pan: the image is larger than the viewport
  /// and left is how you reach the rest of it, so a bounded step moves the
  /// image instead of the selection. Fitted, there is nowhere to pan and the
  /// same key means previous.
  ///
  /// The chrome's Previous/Next deliberately do **not** come through here —
  /// [_viewerChrome] hands them [ImmersiveGalleryViewer.onPrevious] and
  /// [ImmersiveGalleryViewer.onNext] directly, so they select even while
  /// zoomed. A labelled button names a wallpaper; an arrow only names a
  /// direction, and the direction is ambiguous exactly when zoomed. Per slice
  /// 3: "While zoomed, touch input pans and horizontal keys pan by a bounded
  /// step; explicit Previous/Next still selects and resets zoom."
  ///
  /// The reset half is not the viewer's: it resets nothing on selection, since
  /// it does not own the selection. Each session resets its zoom controller
  /// when the selected index changes (see `WallpaperImmersiveSession`), which
  /// covers the buttons, a swipe, and a key alike.
  void _handlePreviousInput() {
    if (_zoomController.isZoomed) {
      _zoomController.panBy(const Offset(48, 0));
      return;
    }
    widget.onPrevious?.call();
  }

  /// Directional right. See [_handlePreviousInput] for why the chrome's
  /// buttons bypass this and select even while zoomed.
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
      onHideChrome: _hideChrome,
      onClose: () => unawaited(_exitFullscreen()),
      position: widget.position,
      itemCount: widget.itemCount,
      // Straight through, not via _handlePreviousInput/_handleNextInput: an
      // explicit button selects even while zoomed (see _handlePreviousInput),
      // and a tear-off is never null, which would silently cost the buttons
      // their boundary-disabled states.
      onPrevious: widget.onPrevious,
      onNext: widget.onNext,
      barActions: widget.barActions,
      actions: <Widget>[
        if (widget.onOpenDetails != null) _openDetailsButton(),
        ...widget.actions,
      ],
    );
  }

  Widget _openDetailsButton() {
    final String label = AppLocalizations.of(context).quickActionOpenDetail;
    return IconButton.filledTonal(
      key: const Key('immersive-viewer-open-details'),
      onPressed: () => unawaited(_openDetails()),
      style: IconButton.styleFrom(
        backgroundColor: Colors.black45,
        foregroundColor: Colors.white,
      ),
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      icon: Icon(Icons.info_outline, semanticLabel: label),
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
