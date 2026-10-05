import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/photo_capsule.dart';
import 'package:tela/features/detail/detail_sheet_progress.dart';

/// The controls drawn over Detail's picture: fullscreen, and the page arrows.
///
/// Each sits in a [PhotoCapsule], the one treatment for a control on a photo —
/// they used to be three (an opaque tonal arrow, a 45% scrim button, and the
/// bar's bare white icons; device survey, 2026-10-05).
///
/// They follow the facts sheet through [DetailSheetProgress]:
/// - **fullscreen is pinned** to the top of the screen. The picture beneath it
///   is bumped up as the sheet rises; riding along, the button left the
///   screen at the sheet's middle stop.
/// - **all of them fade out** over the last half of the sheet's travel
///   ([shownAt]). Near full, the picture is a strip under the app bar, and the
///   arrows clipped into half-circles there. Gone, they take no taps and say
///   nothing to a screen reader; the sheet's grip brings them back.
///
/// ```dart
/// DetailPictureControls(
///   onFullscreen: enter,
///   onPrevious: canGoBack ? back : null,
///   onNext: canGoOn ? next : null,
/// );
/// ```
class DetailPictureControls extends StatelessWidget {
  /// Creates the controls; a null [onPrevious] or [onNext] hides that arrow.
  const DetailPictureControls({
    required this.onFullscreen,
    this.onPrevious,
    this.onNext,
    super.key,
  });

  /// Opens the fullscreen viewer.
  final VoidCallback onFullscreen;

  /// Steps to the previous wallpaper; null when there is none loaded.
  final VoidCallback? onPrevious;

  /// Steps to the next wallpaper; null when there is none loaded.
  final VoidCallback? onNext;

  /// How visible the controls are with the sheet [risen] 0..1 of the way up.
  ///
  /// Fully shown through the first half — the middle stop sits there, and the
  /// picture is still the larger part of the screen — then out by full.
  ///
  /// ```dart
  /// DetailPictureControls.shownAt(0.4); // 1.0
  /// DetailPictureControls.shownAt(1); // 0.0
  /// ```
  static double shownAt(double risen) => ((1 - risen) * 2).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final DetailSheetProgress? progress = DetailSheetProgress.maybeOf(context);
    if (progress == null) return _laidOut(context, lift: 0, shown: 1);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[progress.lift, progress.risen]),
      builder: (BuildContext context, Widget? _) => _laidOut(
        context,
        lift: progress.lift.value,
        shown: shownAt(progress.risen.value),
      ),
    );
  }

  Widget _laidOut(
    BuildContext context, {
    required double lift,
    required double shown,
  }) {
    final bool hidden = shown == 0;
    return IgnorePointer(
      ignoring: hidden,
      child: ExcludeSemantics(
        excluding: hidden,
        child: Opacity(
          opacity: shown,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) => Stack(
              children: <Widget>[
                _arrows(context),
                _fullscreen(context, pinBy: lift * box.maxHeight),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Pinned against the bump by [pinBy] dip, measured where the bar's own
  /// height is already folded in: the Scaffold extends the body behind the
  /// floating bar, so `padding.top` clears its actions in every layout.
  Widget _fullscreen(BuildContext context, {required double pinBy}) {
    return Positioned(
      top: 12 + MediaQuery.paddingOf(context).top + pinBy,
      right: 12,
      child: PhotoCapsule(
        child: IconButton(
          onPressed: onFullscreen,
          tooltip: AppLocalizations.of(context).detailEnterFullscreen,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          icon: const Icon(Icons.fullscreen),
        ),
      ),
    );
  }

  Widget _arrows(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Positioned.fill(
      child: Row(
        children: <Widget>[
          if (onPrevious case final VoidCallback previous)
            _arrow(
              const Key('detail-previous'),
              Icons.chevron_left,
              l10n.galleryPrevious,
              previous,
            ),
          const Spacer(),
          if (onNext case final VoidCallback next)
            _arrow(
              const Key('detail-next'),
              Icons.chevron_right,
              l10n.galleryNext,
              next,
            ),
        ],
      ),
    );
  }

  Widget _arrow(Key key, IconData icon, String tooltip, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: PhotoCapsule(
        child: IconButton(
          key: key,
          onPressed: onTap,
          tooltip: tooltip,
          icon: Icon(icon),
        ),
      ),
    );
  }
}
