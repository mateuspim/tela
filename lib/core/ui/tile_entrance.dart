import 'dart:async';

import 'package:flutter/material.dart';

/// Lifts a wallpaper tile into place the first time it is drawn.
///
/// A wall of thumbnails arriving all at once reads as a screen *replacing*
/// itself; the same wall arriving a few tens of milliseconds apart across a row
/// reads as one assembling. That is the whole effect, and it is deliberately
/// small — a fade and six percent of a tile's height, over [duration].
///
/// **It must fire once per wallpaper, not once per build.** A shelf recycles
/// its rows, so a tile scrolled off and back is a *new* widget for an image the
/// user has already seen; animating that is the wall flickering as you scroll.
/// The caller owns the "already seen" set and answers it through [animate] —
/// see `JustifiedWallpaperGrid`, which is the only place that set can live
/// because it is the only thing that outlives the rows.
///
/// ```dart
/// TileEntrance(
///   animate: firstSighting,
///   delay: Duration(milliseconds: 45 * positionInRow),
///   child: WallpaperTile(wallpaper: wallpaper),
/// );
/// ```
class TileEntrance extends StatefulWidget {
  /// Wraps [child], lifting it in after [delay] when [animate] is true.
  const TileEntrance({
    required this.animate,
    required this.delay,
    required this.child,
    super.key,
  });

  /// Whether this tile has yet to be seen — and whether motion is wanted at
  /// all. False draws [child] in its final state immediately, which is what
  /// both a recycled tile and a reduce-motion device get.
  final bool animate;

  /// How long this tile waits before starting, so a row cascades rather than
  /// flashing as one block.
  final Duration delay;

  /// The tile.
  final Widget child;

  /// How long one tile takes to arrive.
  static const Duration duration = Duration(milliseconds: 260);

  /// How far a tile rises, as a fraction of its own height.
  ///
  /// A fraction rather than a distance so the lift is proportionate at every
  /// tile density — 6% of a *Large* tile and of a *Small* one both read as the
  /// same gesture, where a fixed 12dp would be a shove on one and invisible on
  /// the other.
  static const double lift = 0.06;

  @override
  State<TileEntrance> createState() => _TileEntranceState();
}

class _TileEntranceState extends State<TileEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: TileEntrance.duration,
  );
  Timer? _pending;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) {
      _controller.value = 1;
      return;
    }
    _pending = Timer(widget.delay, _begin);
  }

  /// Guarded because the delay routinely outlives the tile: a fast scroll
  /// disposes a row before its cascade reaches the far end of it.
  void _begin() {
    if (mounted) unawaited(_controller.forward());
  }

  @override
  void dispose() {
    _pending?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Animation<double> eased = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: eased,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, TileEntrance.lift),
          end: Offset.zero,
        ).animate(eased),
        child: widget.child,
      ),
    );
  }
}
