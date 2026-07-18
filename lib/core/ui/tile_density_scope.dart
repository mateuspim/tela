import 'package:flutter/widgets.dart';
import 'package:tela/domain/models/tile_density.dart';

/// Carries the user's chosen [TileDensity] down to every wallpaper shelf.
///
/// The shelves are packed in `core/ui`, which may not reach up into a feature's
/// Riverpod provider — so the app root watches the setting once and publishes
/// it here, and the grid and its skeleton read it from the tree. One wiring
/// point instead of four, which is what keeps Browse, Favorites, History and
/// the private library from drifting into different sizes.
///
/// [of] answers [TileDensity.medium] when no scope is above, so a widget test
/// that mounts a shelf on its own still gets the shipped density rather than an
/// error.
///
/// ```dart
/// TileDensityScope(density: TileDensity.large, child: shelf);
/// TileDensityScope.of(context); // TileDensity.large
/// ```
class TileDensityScope extends InheritedWidget {
  /// Publishes [density] to everything under [child].
  const TileDensityScope({
    required this.density,
    required super.child,
    super.key,
  });

  /// The size the shelves below should draw their tiles at.
  final TileDensity density;

  /// The density in force at [context], or [TileDensity.medium] with no scope
  /// above it.
  static TileDensity of(BuildContext context) {
    final TileDensityScope? scope = context
        .dependOnInheritedWidgetOfExactType<TileDensityScope>();
    return scope?.density ?? TileDensity.medium;
  }

  @override
  bool updateShouldNotify(TileDensityScope oldWidget) =>
      oldWidget.density != density;
}
