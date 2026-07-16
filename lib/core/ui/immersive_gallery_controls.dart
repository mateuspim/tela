import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';

/// Transient, accessible chrome for an immersive gallery surface.
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
    this.primaryAction,
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

  /// A feature's primary action, shown above the navigation row, or null.
  final Widget? primaryAction;

  /// Feature actions shown in the top row, before the close button.
  final List<Widget> actions;

  /// Below this the labelled buttons stop fitting side by side, and become
  /// icons with the same words in their tooltips.
  static const double _compactWidth = 560;

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
            child: Stack(
              children: <Widget>[
                Align(
                  alignment: Alignment.topCenter,
                  child: _controlRow(l10n),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (primaryAction != null) ...<Widget>[
                        primaryAction!,
                        const SizedBox(height: 12),
                      ],
                      _navigationRow(l10n),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controlRow(AppLocalizations l10n) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < _compactWidth;
        return Row(
          children: <Widget>[
            _alignedControl(
              Alignment.centerLeft,
              _leadingControls(l10n, compact: compact),
            ),
            const SizedBox(width: 12),
            _alignedControl(Alignment.centerRight, _trailingControls(l10n)),
          ],
        );
      },
    );
  }

  Widget _leadingControls(AppLocalizations l10n, {required bool compact}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _zoomButton(l10n, compact: compact),
        const SizedBox(width: 8),
        _hideChromeButton(l10n),
      ],
    );
  }

  /// Hides the chrome this button is part of.
  ///
  /// Icon-only, unlike its neighbours: the row already carries a labelled zoom
  /// button and a labelled close, and a third label is what tips it over on a
  /// phone. The tooltip and the semantics label carry the words.
  Widget _hideChromeButton(AppLocalizations l10n) {
    return _tonalControl(
      compact: true,
      key: const Key('immersive-viewer-hide-chrome'),
      label: l10n.galleryHideControls,
      icon: Icons.visibility_off_outlined,
      onPressed: onHideChrome,
    );
  }

  Widget _trailingControls(AppLocalizations l10n) {
    if (actions.isEmpty) return _closeButton(l10n);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final Widget action in actions) ...<Widget>[
          action,
          const SizedBox(width: 8),
        ],
        _closeButton(l10n),
      ],
    );
  }

  Widget _navigationRow(AppLocalizations l10n) {
    return SizedBox(
      height: 48,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < _compactWidth;
          final String positionLabel = l10n.galleryPosition(
            position,
            itemCount,
          );
          return Row(
            children: <Widget>[
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _tonalControl(
                    compact: compact,
                    key: const Key('immersive-viewer-previous'),
                    label: l10n.galleryPrevious,
                    icon: Icons.arrow_back,
                    onPressed: onPrevious,
                  ),
                ),
              ),
              Semantics(
                liveRegion: true,
                label: positionLabel,
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        positionLabel,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _tonalControl(
                    compact: compact,
                    key: const Key('immersive-viewer-next'),
                    label: l10n.galleryNext,
                    icon: Icons.arrow_forward,
                    onPressed: onNext,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// A tonal control that drops its label when the row is too narrow to seat
  /// it — the same trade the navigation row makes, now that the top row has
  /// three controls to fit rather than two.
  Widget _tonalControl({
    required bool compact,
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    if (compact) {
      return IconButton.filledTonal(
        key: key,
        onPressed: onPressed,
        tooltip: label,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        icon: Icon(icon),
      );
    }
    return FilledButton.tonalIcon(
      key: key,
      onPressed: onPressed,
      style: _buttonStyle(),
      icon: Icon(icon),
      label: Text(label),
    );
  }

  Widget _alignedControl(Alignment alignment, Widget child) {
    return Expanded(
      child: Align(alignment: alignment, child: child),
    );
  }

  Widget _zoomButton(AppLocalizations l10n, {required bool compact}) {
    return _tonalControl(
      compact: compact,
      key: const Key('immersive-viewer-zoom'),
      label: zoomed ? l10n.galleryResetZoom : l10n.galleryZoomIn,
      icon: zoomed ? Icons.zoom_out_map : Icons.zoom_in,
      onPressed: onToggleZoom,
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
