import 'package:flutter/material.dart';
import 'package:tela/app/theme.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/browse_filter_text.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';
import 'package:tela/domain/models/search_query.dart';
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
    required this.sorting,
    this.heroTag,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  /// The wallpaper to feature.
  final Wallpaper wallpaper;

  /// The listing this wallpaper is at the top of.
  ///
  /// Named on the band, because "why is this one big?" deserves an answer and
  /// the listing already gives it: on *Most favorited* this **is** the most
  /// favorited wallpaper. The band only ever appears where the order means
  /// better (`Sorting.ranksByMerit`), so the label is always a real claim.
  final Sorting sorting;

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
              // The one tile on the wall drawn large enough that a thumbnail
              // stretched across it reads as blocky.
              quality: TileImageQuality.fullResolution,
            ),
            _Caption(wallpaper: wallpaper, sorting: sorting),
          ],
        ),
      ),
    );
  }
}

/// Why this wallpaper is large, and what it is, over its own wash.
///
/// `IgnorePointer`, so every gesture belongs to the tile underneath and the
/// band stays tappable, long-pressable and selectable across its whole face.
/// Bottom-*left*, because the tile's marks pill owns bottom-right and the two
/// must not collide on a wallpaper that is both featured and already
/// downloaded.
class _Caption extends StatelessWidget {
  const _Caption({required this.wallpaper, required this.sorting});

  final Wallpaper wallpaper;
  final Sorting sorting;

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
          Positioned(left: 16, bottom: 14, child: _lines(context)),
        ],
      ),
    );
  }

  Widget _lines(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(_listing(context), style: _listingStyle(context)),
        const SizedBox(height: 2),
        Text(wallpaper.resolution.toString(), style: _resolutionStyle(context)),
      ],
    );
  }

  /// The listing's own name, from the same `sortingLabel` the tabs use — so the
  /// band cannot claim one thing while the tab above it says another, and no
  /// string was invented for a sentence that already exists.
  String _listing(BuildContext context) =>
      sortingLabel(AppLocalizations.of(context), sorting).toUpperCase();

  /// Small and tracked: a caption naming the claim, not competing with it.
  TextStyle? _listingStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Colors.white70,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w600,
      );

  /// Set in the brand display face rather than a chip: a band this size earns
  /// a line of type, and a pill here would borrow the wall's vocabulary for
  /// something that is not a tile. White, because it sits on a photograph.
  TextStyle? _resolutionStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge?.copyWith(
        fontFamily: TelaTheme.brandFontFamily,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: Colors.white,
      );
}
