import 'package:flutter/widgets.dart';

/// Which wallpapers the user has ticked on one shelf, and whether any are.
///
/// Selection mode has **no flag of its own**: it is active exactly when
/// something is selected. Deselecting the last tile therefore leaves the mode,
/// which is the idiom every gallery on the device already uses, and it keeps
/// this to one piece of state that cannot disagree with itself. Entry is always
/// [selectOnly], so the count is never zero on the way in.
///
/// One shelf owns one of these. It is deliberately not a Riverpod provider:
/// selection is transient view state belonging to a screen, and a global holder
/// for it is the shape B1 retired (`linkedQueryProvider`).
///
/// ```dart
/// final WallpaperSelection selection = WallpaperSelection()
///   ..selectOnly('k8lvqm');
/// ```
class WallpaperSelection extends ChangeNotifier {
  final Set<String> _ids = <String>{};

  /// Whether the shelf is in selection mode.
  bool get isActive => _ids.isNotEmpty;

  /// How many wallpapers are ticked.
  int get count => _ids.length;

  /// The ticked ids, in no meaningful order.
  Set<String> get ids => Set<String>.unmodifiable(_ids);

  /// Whether [wallpaperId] is ticked.
  bool contains(String wallpaperId) => _ids.contains(wallpaperId);

  /// Enters selection mode with [wallpaperId] as the only tick.
  void selectOnly(String wallpaperId) {
    _ids
      ..clear()
      ..add(wallpaperId);
    notifyListeners();
  }

  /// Ticks or unticks [wallpaperId], leaving the mode if it was the last one.
  void toggle(String wallpaperId) {
    if (!_ids.remove(wallpaperId)) _ids.add(wallpaperId);
    notifyListeners();
  }

  /// Ticks every id in [wallpaperIds] that is not already ticked.
  void addAll(Iterable<String> wallpaperIds) {
    final int before = _ids.length;
    _ids.addAll(wallpaperIds);
    if (_ids.length != before) notifyListeners();
  }

  /// Leaves selection mode.
  void clear() {
    if (_ids.isEmpty) return;
    _ids.clear();
    notifyListeners();
  }
}

/// Carries one shelf's [WallpaperSelection] down to its tiles.
///
/// Same shape and same reason as `WallpaperMarksScope`: a tile is packed by
/// `core/ui`'s wall and cannot reach up into the shelf's own state, so the shelf
/// publishes and the tile reads. Unlike the marks, this is an
/// [InheritedNotifier], so a tick rebuilds the tiles without the shelf
/// rebuilding its whole listing.
///
/// [of] answers null with no scope above it, so a shelf mounted on its own in a
/// widget test draws plain tiles rather than throwing — the same courtesy
/// `TileDensityScope` and `WallpaperMarksScope` extend.
class WallpaperSelectionScope extends InheritedNotifier<WallpaperSelection> {
  /// Publishes [selection] to everything under [child].
  const WallpaperSelectionScope({
    required WallpaperSelection selection,
    required super.child,
    super.key,
  }) : super(notifier: selection);

  /// The selection above [context], or null where a shelf has none.
  static WallpaperSelection? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<WallpaperSelectionScope>()
        ?.notifier;
  }

  /// Whether a shelf above [context] is in selection mode.
  static bool isActive(BuildContext context) => of(context)?.isActive ?? false;

  /// Whether [wallpaperId] is ticked on the shelf above [context].
  static bool isSelected(BuildContext context, String wallpaperId) {
    return of(context)?.contains(wallpaperId) ?? false;
  }
}

/// What a tile's tap and long press do, given whether selection is running.
///
/// Extracted because all four wallpaper shelves need the identical rule and
/// none of them should own a copy of it: **in selection mode a tap ticks
/// instead of opening**, and outside it both gestures do whatever the shelf
/// normally does. A shelf that forgot half of that would let the user open a
/// wallpaper while trying to tick it.
///
/// [onOpen] and [onLongPress] are the shelf's own behaviour outside selection
/// mode. Set [longPressSelects] where the shelf has no other use for the
/// gesture and the long press should *enter* selection instead — the two
/// library shelves do, so "long press means select" is one rule there rather
/// than a per-shelf accident. Browse cannot: D1 spent that gesture on the quick
/// sheet, which offers `WallpaperQuickAction.select` as a row instead.
///
/// ```dart
/// final gestures = selectableTileGestures(
///   context: context,
///   wallpaperId: wallpaper.id,
///   onOpen: () => _openDetail(context, loaded, index),
/// );
/// WallpaperTile(onTap: gestures.onTap, onLongPress: gestures.onLongPress);
/// ```
({VoidCallback onTap, VoidCallback? onLongPress}) selectableTileGestures({
  required BuildContext context,
  required String wallpaperId,
  required VoidCallback onOpen,
  VoidCallback? onLongPress,
  bool longPressSelects = false,
}) {
  final WallpaperSelection? selection = WallpaperSelectionScope.of(context);
  if (selection == null) return (onTap: onOpen, onLongPress: onLongPress);
  if (!selection.isActive) {
    return (
      onTap: onOpen,
      onLongPress: longPressSelects
          ? () => selection.selectOnly(wallpaperId)
          : onLongPress,
    );
  }
  void tick() => selection.toggle(wallpaperId);
  return (onTap: tick, onLongPress: tick);
}
