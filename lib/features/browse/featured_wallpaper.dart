import 'package:flutter/material.dart';
import 'package:tela/app/theme.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';

/// The wallpaper at the top of a listing, given the width of the wall.
///
/// Browse's front door. The wall alone opens on a search field, seven tabs and
/// a grid — a *tool*, and one that looks the same whichever listing you are on.
/// This gives the listing a first thing to look at, at a size a wallpaper can
/// be judged at.
///
/// It is the listing's own first item, not a separate request: the band costs
/// no call, and "the top of this listing" is a claim the listing already makes.
/// The wall then continues from the *second* item, so nothing is drawn twice —
/// see `WallpaperGrid`, which owns that offset so the shared grid never learns
/// about it.
///
/// **It is a [WallpaperTile], deliberately, and that is the whole design.** A
/// bespoke band would have to re-implement the marks, the source badge, the
/// selection tick and the ink-above-the-image — and would then be an exception
/// the user has to learn, where a featured wallpaper cannot be ticked or shows
/// no "you already have this". Composing the tile means the band inherits every
/// one of those and cannot drift from the wall. It also keeps the tile order
/// the wall has always had: the featured wallpaper is still the first
/// `WallpaperTile` in the tree, which is why this changed no existing test.
///
/// ```dart
/// FeaturedWallpaper(wallpaper: loaded.first, onTap: open);
/// ```
class FeaturedWallpaper extends StatelessWidget {
  /// Creates the featured band for [wallpaper].
  const FeaturedWallpaper({
    required this.wallpaper,
    this.heroTag,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  /// The wallpaper to feature.
  final Wallpaper wallpaper;

  /// Shared-element tag flying this image into the screen it opens.
  final Object? heroTag;

  /// Called when the band is tapped.
  final VoidCallback? onTap;

  /// Called on a long press — the same quick sheet the tiles offer.
  final VoidCallback? onLongPress;

  /// Fraction of the screen's height the band aims at.
  static const double heightFraction = 0.34;

  /// Ceiling for [heightFraction], so a tablet in landscape does not hand the
  /// whole viewport to one wallpaper and push the wall below the fold.
  static const double maximumHeight = 340;

  @override
  Widget build(BuildContext context) {
    final double height = (MediaQuery.sizeOf(context).height * heightFraction)
        .clamp(200, maximumHeight);
    return Padding(
      padding: const EdgeInsets.only(bottom: wallpaperGridSpacing),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            WallpaperTile(
              wallpaper: wallpaper,
              heroTag: heroTag,
              onTap: onTap,
              onLongPress: onLongPress,
            ),
            _Caption(wallpaper: wallpaper),
          ],
        ),
      ),
    );
  }
}

/// The one fact worth reading before opening a wallpaper, over its own wash.
///
/// `IgnorePointer`, so every gesture belongs to the tile underneath and the
/// band stays tappable, long-pressable and selectable across its whole face.
/// Bottom-*left*, because the tile's marks pill owns bottom-right and the two
/// must not collide on a wallpaper that is both featured and already
/// downloaded.
class _Caption extends StatelessWidget {
  const _Caption({required this.wallpaper});

  final Wallpaper wallpaper;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: <Color>[Color(0x99000000), Color(0x00000000)],
              ),
            ),
          ),
          Positioned(left: 16, bottom: 14, child: _resolution(context)),
        ],
      ),
    );
  }

  /// Set in the brand display face rather than a chip: a band this size earns
  /// a line of type, and a pill here would borrow the wall's vocabulary for
  /// something that is not a tile. White, because it sits on a photograph.
  Widget _resolution(BuildContext context) {
    return Text(
      wallpaper.resolution.toString(),
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontFamily: TelaTheme.brandFontFamily,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: Colors.white,
      ),
    );
  }
}
