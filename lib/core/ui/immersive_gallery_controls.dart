import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/immersive_chrome_palette.dart';

/// Transient, accessible chrome for an immersive gallery surface.
///
/// **The layout is one quiet top row and one action bar, not six pills.** It
/// used to scatter labelled buttons into all four corners — *Zoom in*, hide,
/// *Close*, *Previous*, *Next*, and a counter — each with the same visual
/// weight, on the one screen whose entire job is showing a wallpaper. Now the
/// utilities are icons in the top row, the count is quiet text beside them, and
/// everything a user came here to *do* sits in a single bar along the bottom.
///
/// **Nothing here is a colour constant any more.** Scrim and ink come from
/// [ImmersiveChromePalette], so the fullscreen surface reached from Detail
/// arrives in the wallpaper's own colour instead of staying the black void it
/// was, while the private library and the download viewer — which wrap this in
/// no ambient theme — keep the app's neutral scheme. One code path, and the
/// private library is tinted by nothing.
///
/// Paging kept its buttons rather than deferring to the swipe. They are icons
/// inside that bar now instead of two large pills, but they still exist:
/// swiping is not reachable for someone driving the screen with a screen
/// reader or a switch, so deleting them would trade chrome for access.
class ImmersiveGalleryControls extends StatelessWidget {
  /// Creates zoom, close, position, and gallery navigation controls.
  const ImmersiveGalleryControls({
    required this.visible,
    required this.duration,
    required this.zoomed,
    required this.onToggleZoom,
    required this.onHideChrome,
    required this.onClose,
    required this.position,
    required this.itemCount,
    required this.onPrevious,
    required this.onNext,
    this.barActions = const <Widget>[],
    this.actions = const <Widget>[],
    super.key,
  });

  /// Whether chrome is visible and interactive.
  final bool visible;

  /// Fade duration, or zero when animations are disabled.
  final Duration duration;

  /// Whether the zoom control should offer reset.
  final bool zoomed;

  /// Toggles fitted and zoomed state.
  final VoidCallback onToggleZoom;

  /// Hides this chrome, leaving the image alone on the canvas.
  ///
  /// Hides rather than toggles: the control is only reachable while the chrome
  /// is up, so the other half of the toggle could never be pressed from here.
  /// Bringing it back is the canvas's job: tapping the image shows the chrome
  /// again, and announces as much to a screen reader.
  final VoidCallback onHideChrome;

  /// Closes the fullscreen route.
  final VoidCallback onClose;

  /// One-based selected gallery position.
  final int position;

  /// Number of already-loaded items.
  final int itemCount;

  /// Selects the previous item, or null at the boundary.
  final VoidCallback? onPrevious;

  /// Selects the next item, or null at the boundary.
  final VoidCallback? onNext;

  /// What this surface lets you *do*, seated in the bottom bar between the
  /// paging arrows — favorite and download on the wall, *Set wallpaper* in the
  /// download and private viewers.
  final List<Widget> barActions;

  /// Secondary or destructive actions, kept up in the top row and away from
  /// the bar: the private viewer's delete, the history's overflow.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ImmersiveChromePalette chrome = ImmersiveChromePalette.of(context);
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
            child: Stack(
              children: <Widget>[
                Align(
                  alignment: Alignment.topCenter,
                  child: _topRow(l10n, chrome),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _actionBar(l10n, chrome),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Close on the left, the count and the utilities on the right.
  ///
  /// Close leads because it is the one control every viewer has and the one a
  /// user reaches for most; it keeps a filled treatment where its neighbours
  /// are quiet, so the way out stays obvious without being loud.
  Widget _topRow(AppLocalizations l10n, ImmersiveChromePalette chrome) {
    return Row(
      children: <Widget>[
        _closeButton(l10n),
        const Spacer(),
        _positionLabel(l10n, chrome),
        const SizedBox(width: 8),
        _zoomButton(l10n, chrome),
        const SizedBox(width: 4),
        _hideChromeButton(l10n, chrome),
        for (final Widget action in actions) ...<Widget>[
          const SizedBox(width: 4),
          action,
        ],
      ],
    );
  }

  /// "3 of 72", as text on a scrim rather than as another button.
  ///
  /// It states something instead of doing something, so giving it a button's
  /// weight — which the old floating pill did — made the row read as one more
  /// thing to press. The scrim stays: white text alone vanishes over a pale
  /// wallpaper, the same legibility problem C2's blurred backdrop hit.
  Widget _positionLabel(AppLocalizations l10n, ImmersiveChromePalette chrome) {
    final String label = l10n.galleryPosition(position, itemCount);
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: chrome.scrim,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(label, style: TextStyle(color: chrome.ink)),
          ),
        ),
      ),
    );
  }

  /// Everything actionable, in one container instead of scattered pills.
  ///
  /// Renders even with no [barActions] — the paging arrows live here too, and
  /// a viewer of one image still shows them, disabled, rather than moving the
  /// bar's contents around as a gallery grows.
  Widget _actionBar(AppLocalizations l10n, ImmersiveChromePalette chrome) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: chrome.scrim,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _navigationButton(
              key: const Key('immersive-viewer-previous'),
              label: l10n.galleryPrevious,
              icon: Icons.arrow_back,
              onPressed: onPrevious,
              chrome: chrome,
            ),
            for (final Widget action in barActions) ...<Widget>[
              const SizedBox(width: 4),
              action,
            ],
            const SizedBox(width: 4),
            _navigationButton(
              key: const Key('immersive-viewer-next'),
              label: l10n.galleryNext,
              icon: Icons.arrow_forward,
              onPressed: onNext,
              chrome: chrome,
            ),
          ],
        ),
      ),
    );
  }

  /// Icon-only, on the bar's own scrim rather than carrying a second one.
  Widget _navigationButton({
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required ImmersiveChromePalette chrome,
  }) {
    return IconButton(
      key: key,
      onPressed: onPressed,
      color: chrome.ink,
      disabledColor: chrome.disabledInk,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      // The Icon's `semanticLabel` is the single source of the accessible
      // name. A `tooltip` is *not* a reliable one: measured on this codebase,
      // it exposed no semantics node on one button and a duplicate on
      // another. Icon-only chrome that leaned on tooltips would be silent to
      // a screen reader — which is what the labelled buttons here used to
      // avoid, and what the viewer's a11y test pins.
      icon: Icon(icon, semanticLabel: label),
    );
  }

  /// Hides the chrome this button is part of.
  Widget _hideChromeButton(
    AppLocalizations l10n,
    ImmersiveChromePalette chrome,
  ) {
    return _utilityButton(
      key: const Key('immersive-viewer-hide-chrome'),
      label: l10n.galleryHideControls,
      icon: Icons.visibility_off_outlined,
      onPressed: onHideChrome,
      chrome: chrome,
    );
  }

  /// A top-row utility: icon on a scrim, words in its semantic label.
  ///
  /// These are things you do *to the view* rather than to the wallpaper, so
  /// they stay unlabelled and quiet — the labels were what made the old corner
  /// pills compete with the image.
  Widget _utilityButton({
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required ImmersiveChromePalette chrome,
  }) {
    return IconButton.filledTonal(
      key: key,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: chrome.scrim,
        foregroundColor: chrome.ink,
      ),
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      icon: Icon(icon, semanticLabel: label),
    );
  }

  Widget _zoomButton(AppLocalizations l10n, ImmersiveChromePalette chrome) {
    return _utilityButton(
      key: const Key('immersive-viewer-zoom'),
      label: zoomed ? l10n.galleryResetZoom : l10n.galleryZoomIn,
      icon: zoomed ? Icons.zoom_out_map : Icons.zoom_in,
      onPressed: onToggleZoom,
      chrome: chrome,
    );
  }

  /// The one control that keeps a filled treatment: it is the way out, it is
  /// on every viewer, and it is what a user reaches for most.
  Widget _closeButton(AppLocalizations l10n) {
    return IconButton.filled(
      key: const Key('immersive-viewer-close'),
      onPressed: onClose,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      icon: Icon(Icons.close, semanticLabel: l10n.galleryClose),
    );
  }
}
