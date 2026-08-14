import 'package:flutter/material.dart';
import 'package:tela/core/ui/backdrop_drift_scope.dart';

/// Detail on a phone: the wallpaper full-bleed, its facts on a sheet over it.
///
/// The narrow half of the split C3 built. A phone has no room to put anything
/// *beside* a wallpaper, so the old layout stacked a fixed-height preview above
/// a scrolling panel and the image was a picture in a box. Here the image is
/// the page and everything else rides over it — which is the one arrangement
/// that lets a phone show a wallpaper at the size a wallpaper is judged at.
///
/// **This is not the tablet's layout and must not become it.** With 440dp of
/// pane free beside the image, a sheet over the picture covers the very thing
/// it is describing; the wide layout keeps its two panes. `_expandedWidth` on
/// the detail screen is the only place that choice is made.
///
/// The sheet has three sizes — a peek, a middle 42%, and nearly full — and it
/// snaps between them. It **opens at the peek**, so the wallpaper arrives
/// unobstructed, and raising it *bumps the picture up* rather than covering it.
/// See [peekSheetFraction], which the device demanded.
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

  /// The sheet's middle size — a snap stop between the peek and full.
  ///
  /// The screen no longer *opens* here: see [peekSheetFraction]. It stays as
  /// the size a single upward flick lands on, which is the old resting layout —
  /// enough facts to answer "what is this" without losing the picture.
  static const double restingSheetFraction = 0.42;

  /// The size the screen opens at, and the sheet's floor.
  ///
  /// The device settled this one (SM-X730, 2026-08-14). The screen used to open
  /// at [restingSheetFraction] with no way down, so a phone showed every
  /// wallpaper with its bottom two fifths behind a panel — "the image is behind
  /// the details and i cant hide it", as the owner put it. The wallpaper is the
  /// subject, so it arrives unobstructed and the facts are asked for.
  ///
  /// A peek and not zero: what is left is the grip and the first heading, so
  /// the sheet is still visibly *there* to be pulled up. One that can vanish
  /// is a feature the user has to rediscover.
  static const double peekSheetFraction = 0.12;

  /// How far the sheet rises when dragged up.
  ///
  /// Short of 1 on purpose: a sheet that can cover the screen entirely leaves
  /// the user on a page with no visible way back to the image.
  static const double fullSheetFraction = 0.92;

  /// Breathing room at the foot of the sheet's content.
  static const double sheetFootRoom = 24;

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
  final ValueNotifier<double> _lift = ValueNotifier<double>(0);

  @override
  void dispose() {
    _drift.dispose();
    _lift.dispose();
    super.dispose();
  }

  /// Drifts the scenery, and bumps the wallpaper, as the sheet is moved.
  ///
  /// Three layers at three rates, which is what makes the screen read as having
  /// depth: the sheet travels fastest, the wallpaper is bumped at half that,
  /// and the blurred scenery behind it drifts by 6% of its height over the
  /// whole gesture. Both are measured from the peek, where the screen opens, so
  /// nothing has moved at the moment the user arrives.
  ///
  /// Returns false: the notification keeps bubbling, so nothing above this body
  /// loses the sheet's extent by our listening for it.
  bool _sheetDragged(DraggableScrollableNotification sheet) {
    const double travel =
        DetailEditorialBody.fullSheetFraction -
        DetailEditorialBody.peekSheetFraction;
    final double risen =
        (sheet.extent - DetailEditorialBody.peekSheetFraction) / travel;
    _drift.value = -risen.clamp(0.0, 1.0);
    _lift.value = (sheet.extent - DetailEditorialBody.peekSheetFraction) / 2;
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
    // The button is laid out in normal flow *below* the image, not positioned
    // over it. Absolutely positioning it looked equivalent and was not: its own
    // `SafeArea` had nothing to inset against inside a `Positioned`, so on the
    // device the button ran under the system bar and its label and icon were
    // clipped clean off (seen on the SM-X730, 2026-08-14). Nothing is lost by
    // this — the sheet covers the foot of the screen at every size it can take,
    // so no wallpaper was ever visible behind the button anyway.
    return BackdropDriftScope(
      drift: _drift,
      child: Column(
        children: <Widget>[
          Expanded(
            child: NotificationListener<DraggableScrollableNotification>(
              onNotification: _sheetDragged,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(child: _bumped(widget.preview)),
                  const _TopScrim(),
                  DraggableScrollableSheet(
                    initialChildSize: DetailEditorialBody.peekSheetFraction,
                    minChildSize: DetailEditorialBody.peekSheetFraction,
                    maxChildSize: DetailEditorialBody.fullSheetFraction,
                    // Snapped, so the sheet always comes to rest at one of its
                    // three sizes instead of wherever the finger left it. A
                    // sheet abandoned at 31% is what reads as a stuck scroll.
                    snap: true,
                    snapSizes: const <double>[
                      DetailEditorialBody.restingSheetFraction,
                    ],
                    builder: _sheet,
                  ),
                ],
              ),
            ),
          ),
          _footed(context, widget.applyButton),
        ],
      ),
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
  /// (SM-X730, 2026-08-14).
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

  Widget _sheet(BuildContext context, ScrollController controller) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: DetailEditorialBody.sheetKey,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.only(
          bottom: DetailEditorialBody.sheetFootRoom,
        ),
        children: <Widget>[const _SheetGrip(), widget.metadata],
      ),
    );
  }
}

/// The wash that keeps the back arrow readable over a bright wallpaper.
class _TopScrim extends StatelessWidget {
  const _TopScrim();

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
              colors: <Color>[Color(0x8C000000), Color(0x00000000)],
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
class _SheetGrip extends StatelessWidget {
  const _SheetGrip();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 32,
        height: 4,
        margin: const EdgeInsets.only(top: 12, bottom: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
