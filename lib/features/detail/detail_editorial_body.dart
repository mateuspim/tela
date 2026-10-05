import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tela/core/ui/backdrop_drift_scope.dart';
import 'package:tela/features/detail/detail_sheet_progress.dart';

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
  /// peek is now [sheetGripHeight] and nothing else, which is why widening the
  /// grip's touch target widened the peek with it. It was the grip plus a
  /// "Details" heading on an opaque band, and *"because of that it hides some
  /// of the information of the background"* (2026-08-15). The heading is gone
  /// from `WallpaperMetadata` entirely and the band is gone with it — see
  /// [surfaceAlphaAt]. What is left over the wallpaper is a handle and the
  /// apply button, which is the whole of what a closed sheet has to say.
  static const double peekSheetHeight = sheetGripHeight;

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

  /// The grip's whole vertical footprint **at the peek** — Material's own
  /// minimum touch target, and therefore the closed sheet's whole height.
  ///
  /// It was [sheetGripSettledHeight], the bar plus its margins, which made the
  /// closed sheet 21dp tall: the entire hit area of the only control that
  /// opens the facts, at under half what a thumb is owed. The owner called it
  /// *"kinda hit or miss"* (2026-08-24), and both misses were loud — the apply
  /// button is glued immediately below — they share one surface — and since
  /// pass N the
  /// picture immediately above enters fullscreen on a tap. Nothing about the
  /// screen *looks* different for the change: the sheet is fully transparent
  /// at the peek (see [surfaceAlphaAt]), so what grew is an invisible target,
  /// and the cost is the bottom 48dp of the picture no longer taking a pinch.
  ///
  /// Flutter draws exactly this box for its own handle — `showDragHandle`
  /// constrains it to `kMinInteractiveDimension` — and this sheet only misses
  /// out because it is part of the page rather than presented, so none of that
  /// theming reaches it. See [_SheetGrip].
  static const double sheetGripHeight = kMinInteractiveDimension;

  /// What the grip's band shrinks back to once the panel is solid — the
  /// footprint the bar and its margins had before any of this: 12 + 5 + 4.
  ///
  /// The reach is a closed-sheet problem — open, the handle is decoration and
  /// the facts are already under the thumb — so the target is spent where it
  /// is needed and given back where it is not. Without this an opened sheet
  /// would carry 48dp of blank above its first fact row, which is the kind of
  /// thing the peek's own history says gets noticed on a device.
  ///
  /// The bar is centred in whichever band it has, so growing the closed one
  /// lifts it **away** from the apply button rather than toward it — which is
  /// the half of "hit or miss" that was doing the damage.
  static const double sheetGripSettledHeight = 21;

  /// Stable hook for tests asserting where the sheet has come to rest.
  ///
  /// On the sheet's own surface rather than the `DraggableScrollableSheet`,
  /// which fills the whole body and so reports the screen's rect however far
  /// the sheet has actually risen.
  static const Key sheetKey = Key('detail-editorial-sheet');

  /// Height of the wash behind the app bar's controls.
  ///
  /// A transparent bar over an arbitrary photograph is a back arrow that
  /// vanishes on a pale sky. This is the same argument as `wallpaperTileEdge`
  /// and it is *not* the frosted bar A2 rejected: nothing is blurred, nothing
  /// shows a wall of thumbnails through itself, and there is exactly one image
  /// underneath rather than sixty.
  static const double topScrimHeight = 148;

  /// How far down the wash the app bar's own controls sit.
  ///
  /// The status bar plus half a toolbar: where the back arrow and the actions
  /// are actually drawn, which is the only place this wash has to work.
  static const double topScrimControlRow = 80;

  /// The wash's opacity at the top edge and where it finally reaches zero.
  ///
  /// It **holds** at full strength down to [topScrimControlRow] instead of
  /// fading from the first pixel, which is the whole fix: a straight ramp
  /// spends most of its darkness above the controls, where there is nothing to
  /// read, and arrives at them already half gone. Measured on the device
  /// (SM-X730, 2026-08-14) against a genuinely pale wallpaper, the old ramp
  /// left the white controls at **2.9:1** — over the 3:1 floor for UI graphics
  /// by nothing. Holding the wash rather than steepening it buys the contrast
  /// without making the top edge of every wallpaper darker than it already is.
  static const double topScrimOpacity = 0.6;

  /// The wash's opacity [dip] logical pixels below the top of the screen.
  ///
  /// ```dart
  /// DetailEditorialBody.topScrimAlphaAt(0); // 0.6, full strength
  /// ```
  static double topScrimAlphaAt(double dip) {
    if (dip <= topScrimControlRow) return topScrimOpacity;
    if (dip >= topScrimHeight) return 0;
    final double fade =
        (dip - topScrimControlRow) / (topScrimHeight - topScrimControlRow);
    return topScrimOpacity * (1 - fade);
  }

  /// How long the sheet takes to settle when something other than a finger
  /// moves it. Matches the pager's own page turn, so the screen has one speed.
  static const Duration sheetSettle = Duration(milliseconds: 240);

  /// Raises [sheet] to [restingSheetFraction], unless it is already at least
  /// that far up.
  ///
  /// The guard is not a tidiness check. The upward throw that calls this is
  /// armed across the whole picture, and a picture is still visible above a
  /// fully-raised sheet — so without it, flicking up on a sheet already at
  /// [fullSheetFraction] would *lower* it, which is the opposite of what the
  /// gesture says.
  static Future<void> revealSheet(
    DraggableScrollableController sheet, {
    required bool animate,
  }) {
    if (!sheet.isAttached || sheet.size >= restingSheetFraction) {
      return Future<void>.value();
    }
    return moveSheet(sheet, extent: restingSheetFraction, animate: animate);
  }

  /// Moves [sheet] to [extent], instantly where the platform asked for no
  /// motion.
  ///
  /// Static, and the single spelling of it, because three things now move this
  /// sheet without a finger on it: the grip's tap, the upward throw, and the
  /// return to the peek. A detached controller is an ordinary state, not an
  /// error — the sheet attaches on its first layout, and a gesture can arrive
  /// in the frame before that.
  ///
  /// **The check after the animation is not belt-and-braces.**
  /// `DraggableScrollableController.animateTo` registers an activity on the
  /// sheet, and *any* scroll activity beginning there cancels it — silently,
  /// with a future that then never completes. A Detail screen still arriving
  /// produces exactly those, so a throw in the first moments after opening did
  /// nothing at all (measured 2026-08-24: the first reveal after mount was
  /// swallowed every time, the next one worked). That is the same
  /// "sometimes it doesn't" this whole pass exists to end, so the sheet is put
  /// where it was asked to go.
  ///
  /// Only when it has not moved *at all*: a sheet the user grabbed mid-flight
  /// is somewhere else by now, and yanking it to the target would be the more
  /// annoying bug of the two.
  static Future<void> moveSheet(
    DraggableScrollableController sheet, {
    required double extent,
    required bool animate,
  }) async {
    if (!sheet.isAttached) return;
    if (!animate) {
      sheet.jumpTo(extent);
      return;
    }
    final double before = sheet.size;
    unawaited(
      sheet.animateTo(
        extent,
        duration: sheetSettle,
        curve: Curves.easeOutCubic,
      ),
    );
    await Future<void>.delayed(sheetSettle);
    if (!sheet.isAttached || sheet.size != before) return;
    sheet.jumpTo(extent);
  }

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
              const _TopScrim(),
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
      unawaited(DetailEditorialBody.revealSheet(sheet, animate: animate));
      return;
    }
    unawaited(
      DetailEditorialBody.moveSheet(sheet, extent: _peek, animate: animate),
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
            _SheetGrip(alpha: _surfaceAlpha, onTap: _toggleSheet),
            widget.metadata,
          ],
        ),
      ),
    );
  }
}

/// The wash that keeps the back arrow readable over a bright wallpaper.
class _TopScrim extends StatelessWidget {
  const _TopScrim();

  /// Where the wash stops holding, as a fraction of its own height.
  static const double _controlRowStop =
      DetailEditorialBody.topScrimControlRow /
      DetailEditorialBody.topScrimHeight;

  /// The held colour, and the nothing it fades to.
  static const Color _wash = Color.fromRGBO(
    0,
    0,
    0,
    DetailEditorialBody.topScrimOpacity,
  );
  static const Color _clear = Color.fromRGBO(0, 0, 0, 0);

  @override
  Widget build(BuildContext context) {
    return const Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: DetailEditorialBody.topScrimHeight,
      // Decoration only: the image beneath it still takes every gesture, so
      // the wallpaper can be pinched and held right up to the top edge.
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // Three stops, not two: full strength down past the controls,
              // then out. See DetailEditorialBody.topScrimAlphaAt.
              stops: <double>[0, _controlRowStop, 1],
              colors: <Color>[_wash, _wash, _clear],
            ),
          ),
        ),
      ),
    );
  }
}

/// The handle that says the sheet moves.
///
/// Drawn rather than taken from `BottomSheetThemeData.showDragHandle`, which
/// only applies to a `showModalBottomSheet` — this sheet is part of the page
/// and was never presented, so it inherits none of that theming.
///
/// Its colour travels with the surface it sits on. At rest there is no surface
/// at all — the handle is alone over the photograph, where `onSurfaceVariant`
/// is a mid grey that a pale sky swallows — so it is white there and settles
/// onto the scheme's own colour as the panel fades in.
///
/// White is not enough on its own, and the device proved it twice rather than
/// the argument. On a near-white wallpaper the plain white handle was
/// *invisible*; a shadow alone then measured **1.51:1** against a pure-white
/// one — a soft halo spreads its darkness over too many pixels to be an edge
/// (SM-X730, 2026-08-15). So it carries **both**, at exactly the strength the
/// missing surface owes it and none once the panel is solid: a hairline outline
/// that gives the bar a hard edge on white, and the shadow that lifts it off a
/// busy or mid-toned picture, which an outline alone cannot do.
///
/// Third time this project has paid for the same lesson — see
/// `wallpaperTileEdge` and [DetailEditorialBody.topScrimOpacity]: a control
/// over an arbitrary photograph cannot take its contrast on trust.
class _SheetGrip extends StatelessWidget {
  const _SheetGrip({required this.alpha, this.onTap});

  /// How solid the surface beneath the handle is, 0..1.
  final ValueListenable<double> alpha;

  /// Called when the band around the bar is tapped, to open or close the
  /// sheet. Null leaves the handle drag-only.
  final VoidCallback? onTap;

  /// The bar itself, before either of its defences.
  static const double _barWidth = 32;
  static const double _barHeight = 5;

  /// The outline's and the shadow's strength where the handle is alone over
  /// the wallpaper. Both scale to nothing as the panel fades in.
  static const double _outlineOpacity = 0.7;
  static const double _shadowOpacity = 0.45;

  /// The band's height at [solid] — see
  /// [DetailEditorialBody.sheetGripHeight] for why it is not one number.
  ///
  /// ```dart
  /// _SheetGrip.bandHeightAt(0); // 48, the closed sheet's whole target
  /// ```
  static double bandHeightAt(double solid) {
    return lerpDouble(
      DetailEditorialBody.sheetGripHeight,
      DetailEditorialBody.sheetGripSettledHeight,
      solid.clamp(0.0, 1.0),
    )!;
  }

  @override
  Widget build(BuildContext context) {
    final Color settled = Theme.of(context).colorScheme.onSurfaceVariant;
    // Opaque, so the whole band takes the tap and not just the 32x5 bar drawn
    // in the middle of it. It claims no drag, so the sheet underneath still
    // scrolls out from under a finger that meant to pull rather than tap.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ValueListenableBuilder<double>(
        valueListenable: alpha,
        builder: (BuildContext context, double solid, Widget? child) =>
            SizedBox(
              height: bandHeightAt(solid),
              child: Center(child: _bar(solid, settled)),
            ),
      ),
    );
  }

  Widget _bar(double solid, Color settled) {
    return Container(
      width: _barWidth,
      height: _barHeight,
      decoration: BoxDecoration(
        color: Color.lerp(Colors.white, settled, solid),
        borderRadius: BorderRadius.circular(_barHeight / 2),
        border: Border.all(
          color: Colors.black.withValues(
            alpha: _outlineOpacity * (1 - solid),
          ),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(
              alpha: _shadowOpacity * (1 - solid),
            ),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}
