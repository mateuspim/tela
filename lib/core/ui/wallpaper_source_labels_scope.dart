import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Carries each source's display name down to every shelf's tiles.
///
/// Same shape and same reason as `WallpaperMarksScope`: a tile packed in
/// `core/ui`'s wall may not reach up into the source registry provider, and a
/// family watch per tile — on a wall of several hundred — is exactly the cost
/// C4 warned about. The app root watches the registry once and publishes this
/// tiny id→name map, which changes only when a source is registered or retired,
/// i.e. effectively never at runtime.
///
/// [labelFor] answers null when no scope is above it, so a widget test that
/// mounts a shelf alone draws no badge rather than throwing — the same
/// graceful-empty `WallpaperMarksScope` gives its marks.
///
/// ```dart
/// WallpaperSourceLabelsScope(
///   labels: <String, String>{'wallhaven': 'Wallhaven'},
///   child: shelf,
/// );
/// ```
class WallpaperSourceLabelsScope extends InheritedWidget {
  /// Publishes the id→name map to everything under [child].
  const WallpaperSourceLabelsScope({
    required this.labels,
    required super.child,
    super.key,
  });

  /// `SourceId.value` → the source's human name, e.g. `'wallhaven'` →
  /// `'Wallhaven'`. One entry per registered source.
  final Map<String, String> labels;

  /// The display name for [sourceValue], or null when it is unknown — an absent
  /// scope, or a stored row written by a build that had a source this one has
  /// since retired. A null draws no badge rather than a raw lowercase id.
  static String? labelFor(BuildContext context, String sourceValue) {
    final WallpaperSourceLabelsScope? scope = context
        .dependOnInheritedWidgetOfExactType<WallpaperSourceLabelsScope>();
    return scope?.labels[sourceValue];
  }

  /// Compares by contents, not identity: the map is rebuilt from the registry
  /// on every unrelated root rebuild, so an identity check would re-badge the
  /// whole wall each time.
  @override
  bool updateShouldNotify(WallpaperSourceLabelsScope oldWidget) =>
      !mapEquals(oldWidget.labels, labels);
}
