import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_viewport.dart';
import 'package:tela/core/ui/gallery_zoom_animator.dart';
import 'package:tela/core/ui/gallery_zoom_controller.dart';
import 'package:tela/core/ui/immersive_chrome_palette.dart';
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

  /// How long the chrome stays up with nothing touching it.
  ///
  /// The viewer opens with its controls *visible* and only then fades them,
  /// rather than opening bare: a first-time user has to be shown the way out
  /// before it goes. Three seconds is long enough to read the row and short
  /// enough that a wallpaper you are actually looking at is soon unobstructed.
  static const Duration _chromeIdleTimeout = Duration(seconds: 3);

  late GalleryZoomController _zoomController;
  late bool _ownsZoomController;
  late final GalleryZoomAnimator _zoomAnimator;
  late final ImmersiveSystemUi _activeSystemUi;
  late final Future<void> _enterSystemUi;
  bool _chromeVisible = true;
  bool _systemUiRestored = false;
  bool _isExiting = false;
  bool _allowPop = false;
  Timer? _chromeIdle;
  bool _armedOnce = false;
  double _dismissDrag = 0;

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

  /// Arms the idle fade on the first frame that has a [MediaQuery] to read.
  ///
  /// Not [initState]: whether the chrome may fade at all depends on
  /// [MediaQueryData.accessibleNavigation], and there is no inherited widget to
  /// ask in there. Guarded so that an ordinary dependency change — a rotation,
  /// a theme crossfade — cannot keep pushing the fade further away.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_armedOnce) return;
    _armedOnce = true;
    _armChromeIdle();
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
    _chromeIdle?.cancel();
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
    _armChromeIdle();
  }

  /// Starts the countdown that hides the chrome, or cancels it.
  ///
  /// Three things it must not do, and each of them is a test:
  ///
  /// It never fades while a screen reader or a switch is driving the screen.
  /// Chrome that vanishes on a clock is chrome an assistive user cannot get
  /// back to — the way back is a tap on the canvas, which is a gesture, and a
  /// gesture is exactly what that user does not have. So the timeout is a
  /// sighted-touch affordance and [MediaQueryData.accessibleNavigation] turns
  /// it off entirely.
  ///
  /// It never runs while the chrome is already hidden, which would otherwise
  /// leave a timer alive for the whole session doing nothing.
  ///
  /// And it never fires after the route is gone: [dispose] cancels it. A
  /// pending timer outliving its widget is both a leak and a test failure.
  void _armChromeIdle() {
    _chromeIdle?.cancel();
    _chromeIdle = null;
    if (!_chromeVisible) return;
    if (MediaQuery.accessibleNavigationOf(context)) return;
    _chromeIdle = Timer(_chromeIdleTimeout, _hideChrome);
  }

  /// Restarts the countdown on any touch, so the chrome never fades out from
  /// under a finger that is reaching for it.
  ///
  /// A [Listener] rather than a gesture: this sits above the whole surface and
  /// must see the pointer without competing for it — taking it would cost the
  /// canvas its pinch, which is the trap `ShelfSwipe` documents at length.
  void _touched(PointerDownEvent event) {
    _armChromeIdle();
  }

  /// Hides the chrome from the chrome's own button.
  ///
  /// The button goes away with everything else it sits among, so this is a
  /// one-way door and the canvas is the way back: tapping the image calls
  /// [_toggleChrome], and the canvas's semantics label announces exactly that
  /// (`galleryShowControls`) for a screen reader. Those two are what keep this
  /// from being a control that hides itself for good.
  void _hideChrome() {
    _chromeIdle?.cancel();
    _chromeIdle = null;
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

  /// How far down the canvas has been thrown, as a share of the distance that
  /// commits the dismiss. Clamped, because a finger can travel further than
  /// the threshold before it lifts.
  double get _dismissProgress {
    return (_dismissDrag / ShelfSwipe.dismissThreshold).clamp(0.0, 1.0);
  }

  void _dragCanvasDown(double distance) {
    if (distance == _dismissDrag) return;
    setState(() => _dismissDrag = distance);
  }

  void _dismissByThrow() {
    unawaited(_exitFullscreen());
  }

  /// Follows the finger on the way down, and springs back if it falls short.
  ///
  /// The duration is the tell: zero while the throw is live, so the picture is
  /// under the finger rather than trailing it, and the chrome's own fade on the
  /// way back, so an abandoned throw settles instead of snapping.
  Widget _throwableCanvas(Widget canvas) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _dismissDrag),
      duration: _dismissDrag == 0 ? _chromeDuration() : Duration.zero,
      curve: Curves.easeOut,
      child: canvas,
      builder: (BuildContext context, double drag, Widget? child) {
        return Transform.translate(
          offset: Offset(0, drag),
          child: Opacity(opacity: _thrownOpacity(drag), child: child),
        );
      },
    );
  }

  /// The picture dims as it is thrown, but never past half — it has to stay
  /// legible enough that a user who changes their mind can see what they are
  /// dragging back.
  double _thrownOpacity(double drag) {
    final double progress = (drag / ShelfSwipe.dismissThreshold).clamp(
      0.0,
      1.0,
    );
    return 1 - progress * 0.5;
  }

  Widget _imageCanvas(AppLocalizations l10n) {
    return ShelfSwipe(
      isZoomed: _zoomController.isZoomed,
      onPrevious: widget.onPrevious,
      onNext: widget.onNext,
      onHold: widget.onHold,
      onDragDown: _dragCanvasDown,
      onDismiss: _dismissByThrow,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: _chromeVisible
            ? l10n.galleryHideControls
            : l10n.galleryShowControls,
        onTap: _toggleChrome,
        child: _throwableCanvas(
          GalleryViewport(
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
      // A throw in progress hides the chrome without touching `_chromeVisible`,
      // so abandoning the throw brings back exactly the controls that were up.
      visible: _chromeVisible && _dismissProgress == 0,
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
    final ImmersiveChromePalette chrome = ImmersiveChromePalette.of(context);
    return IconButton.filledTonal(
      key: const Key('immersive-viewer-open-details'),
      onPressed: () => unawaited(_openDetails()),
      style: IconButton.styleFrom(
        backgroundColor: chrome.scrim,
        foregroundColor: chrome.ink,
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
          child: Listener(
            onPointerDown: _touched,
            child: Material(
              // Black, and deliberately still black after N1 tinted the chrome
              // around it. The owner was asked how far the wallpaper's colour
              // should reach and chose the controls only: a letterbox glowing
              // in the picture's own hue competes with the picture, on the one
              // surface where it is largest. `ImmersiveChromePalette` is where
              // the tint stops.
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
      ),
    );
  }
}
