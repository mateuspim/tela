import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tela/core/ui/backdrop_drift_scope.dart';
import 'package:tela/features/detail/detail_sheet_grip.dart';
import 'package:tela/features/detail/detail_sheet_motion.dart';
import 'package:tela/features/detail/detail_sheet_progress.dart';
import 'package:tela/features/detail/detail_top_scrim.dart';

/// Detail, at every width: the wallpaper full-bleed, its facts on a sheet.
///
/// Built as the narrow half of the split C3 made. A phone has no room to put
/// anything *beside* a wallpaper, so the old layout stacked a fixed-height
/// preview above a scrolling panel and the image was a picture in a box. Here
/// the image is the page and everything else rides over it — the one
/// arrangement that shows a wallpaper at the size a wallpaper is judged at.
///
/// **It used to say it must not become the tablet's layout, and it now is it.**
/// The argument for the two panes was real: with 440dp free beside the image, a
/// sheet over the picture covers the very thing it describes. What beat it was
/// use — the owner drove both on an SM-X730 and chose this one (2026-08-14).
/// Three of the four things below are compact-only by construction, and the
/// tablet had none of them: the peek the wallpaper arrives behind, the snapping
/// between three sizes, and the bump. The fourth, the scenery drift, reached
/// the pane in the one form that fails silently — the pane's own scroll drove
/// it, and an ordinary wallpaper's facts hold about 180dp of scroll, so on many
/// wallpapers nothing moved at all. One layout answers all four at once, which
/// is why this is not a patch to the pane.
///
/// The sheet has three sizes — a peek, a middle 42%, and nearly full — and it
/// snaps between them. It **opens at the peek**, so the wallpaper arrives
/// unobstructed, and raising it *bumps the picture up* rather than covering it.
/// See [peekSheetHeight], which the device demanded twice — once for the peek
/// itself and once for it being a height rather than a fraction.
///
/// It also owns the one moving part of the arrangement: dragging the sheet
/// drifts the wallpaper's blurred scenery behind it, published through a
/// `BackdropDriftScope`. That is the parallax the browse wall could not have —
/// nothing on a shelf may be cropped, and the letterbox backdrop already is.
///
/// Pure layout: it takes the three pieces already built and arranges them, so
/// it can be tested without a wallpaper, a source, or a network.
///
/// ```dart
/// DetailEditorialBody(
///   preview: DetailPreviewPager(...),
///   metadata: WallpaperMetadata(...),
///   applyButton: DetailApplyButton(wallpaper: wallpaper),
/// );
/// ```
class DetailEditorialBody extends StatefulWidget {
  /// Arranges [preview], [metadata] and [applyButton] as one page.
  const DetailEditorialBody({
    required this.preview,
    required this.metadata,
    required this.applyButton,
    this.sheetController,
    super.key,
  });

  /// The wallpaper itself, filling the screen behind everything.
  final Widget preview;

  /// The facts, carried by the draggable sheet.
  final Widget metadata;

  /// The apply action, held below the sheet and never scrolled away.
  ///
  /// Outside the scrolling content on purpose: the whole app is three taps to a
  /// wallpaper, and a button you must first scroll to is a fourth.
  final Widget applyButton;

  /// The handle on the facts sheet, for whatever opens it from outside.
  ///
  /// Owned by the screen rather than created here, because the other thing
  /// that opens this sheet is a gesture on [preview] — a widget built by that
  /// same screen and handed to this one, which therefore cannot reach into
  /// this State to ask. Null leaves the sheet reachable only by dragging it,
  /// which is what every test that mounts this body on its own gets.
  final DraggableScrollableController? sheetController;

  /// The sheet's middle size — a snap stop between the peek and full.
  ///
  /// The screen no longer *opens* here: see [peekSheetHeight]. It stays as
  /// the size a single upward flick lands on, which is the old resting layout —
  /// enough facts to answer "what is this" without losing the picture.
  static const double restingSheetFraction = 0.42;

  /// The size the screen opens at, and the sheet's floor — **in dip, not a
  /// fraction.**
  ///
  /// The device settled that there *is* a peek (SM-X730, 2026-08-14). The
  /// screen used to open at [restingSheetFraction] with no way down, so a phone
  /// showed every wallpaper with its bottom two fifths behind a panel — "the
  /// image is behind the details and i cant hide it", as the owner put it. The
  /// wallpaper is the subject, so it arrives unobstructed and the facts are
  /// asked for.
  ///
  /// It settled the *unit* a day later — a fraction landed inside the first
  /// fact row and sliced it in half — and then settled the **contents**: the
  /// peek is now [DetailSheetGrip.height] and nothing else, which is why
  /// widening the grip's touch target widened the peek with it. It was the grip
  /// plus a "Details" heading on an opaque band, and *"because of that it hides
  /// some of the information of the background"* (2026-08-15). The heading is
  /// gone from `WallpaperMetadata` entirely and the band is gone with it — see
  /// [surfaceAlphaAt]. What is left over the wallpaper is a handle and the
  /// apply button, which is the whole of what a closed sheet has to say.
  static const double peekSheetHeight = DetailSheetGrip.height;

  /// [peekSheetHeight] as a fraction of a sheet box [arena] dip tall.
  ///
  /// Clamped below [restingSheetFraction] so the snap stop always stays above
  /// the floor: on a very short box — a split-screen window, a landscape phone
  /// — the heading's own height could otherwise exceed the resting size, and
  /// `DraggableScrollableSheet` asserts on a snap size outside its range.
  ///
  /// ```dart
  /// DetailEditorialBody.peekFractionIn(800); // 0.085
  /// ```
  static double peekFractionIn(double arena) {
    if (arena <= 0) return restingSheetFraction;
    return (peekSheetHeight / arena).clamp(0.0, restingSheetFraction);
  }

  /// How far the sheet rises when dragged up.
  ///
  /// Short of 1 on purpose: a sheet that can cover the screen entirely leaves
  /// the user on a page with no visible way back to the image.
  static const double fullSheetFraction = 0.92;

  /// Breathing room at the foot of the sheet's content.
  static const double sheetFootRoom = 24;

  /// How opaque the sheet's own surface is at [extent], 0..1.
  ///
  /// The sheet used to be a solid panel at every size, so its closed state put
  /// an opaque band across the foot of the picture — *"it hides some of the
  /// information of the background"*, and *"make like a the handle invisible
  /// and when we are opening it up it starts to have background color fading
  /// it in until it reaches a certain point that it shows the details page"*
  /// (the owner, 2026-08-15). So: nothing at the peek, and full by
  /// [restingSheetFraction], which is the first stop it snaps to and therefore
  /// the "certain point" — the sheet is a solid page everywhere it comes to
  /// rest, and glass only while it is actually moving.
  ///
  /// Takes [floor] rather than reading [peekSheetHeight], because the floor is
  /// a height converted against a box only the layout has measured.
  ///
  /// ```dart
  /// DetailEditorialBody.surfaceAlphaAt(extent: 0.42, floor: 0.03); // 1.0
  /// ```
  static double surfaceAlphaAt({
    required double extent,
    required double floor,
  }) {
    final double travel = restingSheetFraction - floor;
    if (travel <= 0) return 1;
    return ((extent - floor) / travel).clamp(0.0, 1.0);
  }

  /// Stable hook for tests asserting where the sheet has come to rest.
  ///
  /// On the sheet's own surface rather than the `DraggableScrollableSheet`,
  /// which fills the whole body and so reports the screen's rect however far
  /// the sheet has actually risen.
  static const Key sheetKey = Key('detail-editorial-sheet');

  @override
  State<DetailEditorialBody> createState() => _DetailEditorialBodyState();
}

class _DetailEditorialBodyState extends State<DetailEditorialBody> {
  /// How far the wallpaper's own blurred scenery has drifted, -1..1.
  ///
  /// A notifier rather than `setState` because the sheet reports every frame of
  /// a drag: rebuilding this body would rebuild the preview, the pager and the
  /// sheet's whole list to move a background by a few pixels.
  final ValueNotifier<double> _drift = ValueNotifier<double>(0);

  /// How far the wallpaper itself is bumped up, as a fraction of its height.
  ///
  /// The sheet does not cover the picture, it *pushes* it: rising by half of
  /// what the sheet takes keeps the image centred in the strip left above it,
  /// so raising the facts moves the wallpaper out of their way instead of
  /// hiding it. Half, so the preview's own bottom edge always stays under the
  /// sheet — a full-rate lift would open a gap of dead canvas beneath it.
  ///
  /// The sheet's extent is a fraction of the body *minus the apply button*,
  /// while this is a fraction of the whole body, so since the picture went
  /// full-bleed the lift is a hair more than half the sheet's travel. Left
  /// alone deliberately: the number was tuned by eye on a device and the
  /// difference is the button's height halved, which is not a thing an eye can
  /// find. Re-tune it from a device or not at all.
  final ValueNotifier<double> _lift = ValueNotifier<double>(0);

  /// How far the sheet has travelled from the peek to full, 0..1 — what the
  /// controls over the picture fade by (see `DetailSheetProgress`).
  final ValueNotifier<double> _risen = ValueNotifier<double>(0);

  /// How solid the sheet's surface is, 0..1 — see
  /// [DetailEditorialBody.surfaceAlphaAt].
  ///
  /// Shared by the sheet and by the block behind the apply button, which is
  /// what makes the two read as one panel rather than two things that happen
  /// to be near each other.
  final ValueNotifier<double> _surfaceAlpha = ValueNotifier<double>(0);

  /// The floor the current box works out to, written by the layout that
  /// measured it and read by the grip's tap, which needs to know what
  /// "closed" means before it can put the sheet back there.
  double _peek = DetailEditorialBody.restingSheetFraction;

  @override
  void dispose() {
    _drift.dispose();
    _lift.dispose();
    _risen.dispose();
    _surfaceAlpha.dispose();
    super.dispose();
  }

  /// Drifts the scenery, and bumps the wallpaper, as the sheet is moved.
  ///
  /// Three layers at three rates, which is what makes the screen read as having
  /// depth: the sheet travels fastest, the wallpaper is bumped at half that,
  /// and the blurred scenery behind it drifts by 6% of its height over the
  /// whole gesture. Both are measured from the notification's own `minExtent`
  /// — the peek, where the screen opens — so nothing has moved at the moment
  /// the user arrives, and neither has to know that the floor is now computed
  /// from a height rather than named as a fraction.
  ///
  /// Returns false: the notification keeps bubbling, so nothing above this body
  /// loses the sheet's extent by our listening for it.
  bool _sheetDragged(DraggableScrollableNotification sheet) {
    final double travel = sheet.maxExtent - sheet.minExtent;
    if (travel <= 0) return false;
    final double risen = (sheet.extent - sheet.minExtent) / travel;
    _risen.value = risen.clamp(0.0, 1.0);
    _drift.value = -_risen.value;
    _lift.value = (sheet.extent - sheet.minExtent) / 2;
    _surfaceAlpha.value = DetailEditorialBody.surfaceAlphaAt(
      extent: sheet.extent,
      floor: sheet.minExtent,
    );
    return false;
  }

  /// The wallpaper, bumped up by whatever the sheet has taken from it.
  ///
  /// Only the translation rebuilds: the preview is the builder's `child`, so a
  /// drag never rebuilds the pager or re-requests an image.
  Widget _bumped(Widget preview) {
    return ValueListenableBuilder<double>(
      valueListenable: _lift,
      builder: (BuildContext context, double lift, Widget? child) =>
          FractionalTranslation(
            translation: Offset(0, -lift),
            child: child,
          ),
      child: preview,
    );
  }

  @override
  Widget build(BuildContext context) {
    // The wallpaper is the whole body, and the sheet and the button ride over
    // it. It used to be the top cell of a `Column` whose bottom cell was the
    // button, which cost the picture the button's height at every sheet size —
    // "make the fullscreen so that i can see the full background", as the owner
    // put it on the tablet (2026-08-15). The image is `BoxFit.contain`, so the
    // taller box is not decoration: it is what the picture is *fitted* to, and
    // on a 1205x753dp screen the letterbox bands close by that much.
    //
    // The `Column` stays, and holds only the two overlays. Everything it lays
    // out keeps measuring against the same box it always did, so the sheet's
    // three tuned fractions and the button's inset all mean exactly what they
    // meant before — what changed is the layer *behind* them.
    return BackdropDriftScope(
      drift: _drift,
      child: DetailSheetProgress(
        lift: _lift,
        risen: _risen,
        child: NotificationListener<DraggableScrollableNotification>(
          onNotification: _sheetDragged,
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: _bumped(widget.preview)),
              const DetailTopScrim(),
              Column(
                children: <Widget>[
                  Expanded(child: _draggableSheet()),
                  _glued(_footed(context, widget.applyButton)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The sheet, which paints only where it has risen to.
  ///
  /// Nothing outside it is hit-testable, which is what lets the wallpaper under
  /// the whole `Column` still take the pinch and the hold-to-copy.
  ///
  /// Behind a `LayoutBuilder` because the floor is a height and this widget
  /// only speaks fractions — and the box to divide by is this one, the body
  /// *minus the apply button*, which no `MediaQuery` above knows.
  Widget _draggableSheet() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints arena) {
        final double peek = DetailEditorialBody.peekFractionIn(arena.maxHeight);
        _peek = peek;
        return DraggableScrollableSheet(
          controller: widget.sheetController,
          initialChildSize: peek,
          minChildSize: peek,
          maxChildSize: DetailEditorialBody.fullSheetFraction,
          // Snapped, so the sheet always comes to rest at one of its three
          // sizes instead of wherever the finger left it. A sheet abandoned at
          // 31% is what reads as a stuck scroll.
          snap: true,
          snapSizes: const <double>[DetailEditorialBody.restingSheetFraction],
          builder: _sheet,
        );
      },
    );
  }

  /// Lifts [child] clear of the system bar, from [MediaQuery.viewPaddingOf].
  ///
  /// The button carries a `SafeArea` of its own and it is not enough here: this
  /// body runs under a Scaffold with `extendBodyBehindAppBar`, and the bottom
  /// `padding` reaching the button comes through as zero — so on the device the
  /// apply button was drawn half under the system bar with its label cut clean
  /// off, while the same widget in the wide layout was fine. Verified by
  /// deploying the build before this layout, where it rendered correctly
  /// (SM-X730, 2026-08-14). **This is the reason the button is laid out by a
  /// `Column` rather than a `Positioned`** — inside a `Positioned` its own
  /// `SafeArea` has nothing to inset against, and the same clipping returns.
  ///
  /// `viewPadding` rather than `padding` because `viewPadding` always reports
  /// the real inset and is never consumed by an ancestor; the button's own
  /// `SafeArea` is stripped here so the two cannot both apply.
  Widget _footed(BuildContext context, Widget child) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: child,
      ),
    );
  }

  /// Paints [child]'s block in the sheet's own surface, at the sheet's own
  /// opacity.
  ///
  /// The apply button and the sheet *"seem disconnected"* — the owner's word,
  /// looking at the strip of wallpaper that ran between the sheet's bottom edge
  /// and the button below it (2026-08-15). They abut exactly, and share this
  /// colour, so they rise and solidify as one panel. Squared off rather than
  /// rounded on purpose: this is the panel's middle, not its top.
  Widget _glued(Widget child) {
    return ValueListenableBuilder<double>(
      valueListenable: _surfaceAlpha,
      builder: (BuildContext context, double alpha, Widget? built) =>
          ColoredBox(color: _surface(context, alpha), child: built),
      child: child,
    );
  }

  /// The sheet's colour at [alpha], from the wallpaper's own ambient scheme.
  Color _surface(BuildContext context, double alpha) =>
      Theme.of(context).colorScheme.surface.withValues(alpha: alpha);

  /// Opens the sheet to its first stop, or puts it back at the peek.
  ///
  /// A tap rather than only a drag, because the grip is what a user reaches
  /// for and tapping a handle is the cheaper gesture — and because it gives
  /// the upward throw a labelled, screen-reader-reachable equivalent, which is
  /// the rule `ShelfSwipe.onSwipeUp` is held to.
  void _toggleSheet() {
    final DraggableScrollableController? sheet = widget.sheetController;
    if (sheet == null || !sheet.isAttached) return;
    final bool animate = !MediaQuery.disableAnimationsOf(context);
    if (sheet.size < DetailEditorialBody.restingSheetFraction) {
      unawaited(DetailSheetMotion.revealSheet(sheet, animate: animate));
      return;
    }
    unawaited(
      DetailSheetMotion.moveSheet(sheet, extent: _peek, animate: animate),
    );
  }

  Widget _sheet(BuildContext context, ScrollController controller) {
    return ValueListenableBuilder<double>(
      valueListenable: _surfaceAlpha,
      builder: (BuildContext context, double alpha, Widget? built) =>
          DecoratedBox(
            key: DetailEditorialBody.sheetKey,
            decoration: BoxDecoration(
              color: _surface(context, alpha),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: built,
          ),
      // A `SingleChildScrollView` and not a `ListView`, since the peek shrank
      // to the handle alone. A lazy sliver builds nothing past its viewport,
      // and 20dp of viewport is exactly the handle — so the facts were not in
      // the tree at all until the sheet was pulled, and `cacheExtent` does not
      // rescue it (measured: 2000dp of cache still built one child). This
      // content is one fixed column of facts, never a long list, so building
      // it eagerly costs a layout nobody notices and buys a pull-up that has
      // nothing left to construct.
      child: SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.only(
          bottom: DetailEditorialBody.sheetFootRoom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DetailSheetGrip(alpha: _surfaceAlpha, onTap: _toggleSheet),
            widget.metadata,
          ],
        ),
      ),
    );
  }
}
