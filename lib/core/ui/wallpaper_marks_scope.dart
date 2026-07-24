import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

/// One "you already have this" claim a tile can make about a wallpaper.
///
/// UI vocabulary, not a domain concept: the domain has favorites and download
/// records, and this is only the question of which of them a tile draws.
enum WallpaperMark {
  /// The wallpaper is in the user's favorites.
  favorited,

  /// tela has downloaded the wallpaper to this device at least once.
  downloaded,
}

/// Carries "which wallpapers do I already have" down to every shelf's tiles.
///
/// Same shape and same reason as `TileDensityScope`: the tile is packed in
/// `core/ui`'s wall and may not reach up into a feature's Riverpod provider, so
/// the app root watches the two set-shaped providers once and publishes them
/// here. One watch for the whole app rather than a family watch per tile, which
/// on a wall of several hundred tiles is the difference that matters.
///
/// [marksFor] answers the empty set when no scope is above it, so a widget test
/// that mounts a shelf on its own draws unmarked tiles rather than throwing —
/// which is why no existing shelf test needed touching.
///
/// ```dart
/// WallpaperMarksScope(
///   favorited: <String>{'wallhaven-e7jvjd'},
///   downloaded: <String>{},
///   child: shelf,
/// );
/// ```
class WallpaperMarksScope extends InheritedWidget {
  /// Publishes both key sets to everything under [child].
  const WallpaperMarksScope({
    required this.favorited,
    required this.downloaded,
    required super.child,
    super.key,
  });

  /// [WallpaperRef.key] of every favorited wallpaper — source-qualified, since
  /// the library holds wallpapers from more than one site.
  final Set<String> favorited;

  /// [WallpaperRef.key] of every wallpaper downloaded to this device.
  final Set<String> downloaded;

  /// The marks [wallpaperKey] has earned, narrowed to those the shelf shows.
  ///
  /// [visible] is what lets a shelf drop a mark that would be true on every one
  /// of its tiles and therefore says nothing — a heart on all of Favorites.
  static Set<WallpaperMark> marksFor(
    BuildContext context,
    String wallpaperKey,
    Set<WallpaperMark> visible,
  ) {
    final WallpaperMarksScope? scope = context
        .dependOnInheritedWidgetOfExactType<WallpaperMarksScope>();
    if (scope == null) return const <WallpaperMark>{};
    return <WallpaperMark>{
      if (visible.contains(WallpaperMark.favorited) &&
          scope.favorited.contains(wallpaperKey))
        WallpaperMark.favorited,
      if (visible.contains(WallpaperMark.downloaded) &&
          scope.downloaded.contains(wallpaperKey))
        WallpaperMark.downloaded,
    };
  }

  /// Compares by contents, not identity: both sets are rebuilt from scratch
  /// every time their provider recomputes, so an identity check would report a
  /// change on every unrelated rebuild and re-mark the whole wall.
  @override
  bool updateShouldNotify(WallpaperMarksScope oldWidget) =>
      !setEquals(oldWidget.favorited, favorited) ||
      !setEquals(oldWidget.downloaded, downloaded);
}
