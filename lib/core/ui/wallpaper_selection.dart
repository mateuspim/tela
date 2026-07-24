import 'package:flutter/material.dart';

/// Which wallpapers the user has ticked on one shelf, and whether the shelf is
/// selecting at all.
///
/// **Selection mode is an explicit flag, and it has to be.** It was originally
/// derived — active exactly when something was ticked, so unticking the last
/// tile left the mode — which is tidier and was right while the only way in was
/// a long press that ticked something. An app-bar *Select* button has no tile
/// to tick, so under the derived rule pressing it did nothing at all. The flag
/// is the cost of an entry point that does not depend on a wallpaper.
///
/// The consequence to know: **unticking everything keeps you in the mode**,
/// showing an empty bar with its actions disabled, and only [clear] leaves.
/// That is also the friendlier half of the trade — a mis-tap on your last
/// ticked tile no longer throws away the mode along with the tick.
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

  /// Whether the shelf is selecting, independently of anything being ticked.
  bool _active = false;

  /// Whether the shelf is in selection mode.
  bool get isActive => _active;

  /// How many wallpapers are ticked.
  int get count => _ids.length;

  /// The ticked keys, in no meaningful order.
  Set<String> get ids => Set<String>.unmodifiable(_ids);

  /// Whether [wallpaperKey] is ticked.
  bool contains(String wallpaperKey) => _ids.contains(wallpaperKey);

  /// Enters selection mode with nothing ticked — what a *Select* button does.
  void enter() {
    if (_active) return;
    _active = true;
    notifyListeners();
  }

  /// Enters selection mode with [wallpaperKey] as the only tick.
  void selectOnly(String wallpaperKey) {
    _active = true;
    _ids
      ..clear()
      ..add(wallpaperKey);
    notifyListeners();
  }

  /// Ticks or unticks [wallpaperKey], staying in the mode either way.
  void toggle(String wallpaperKey) {
    if (!_ids.remove(wallpaperKey)) _ids.add(wallpaperKey);
    notifyListeners();
  }

  /// Ticks every key in [wallpaperKeys] that is not already ticked.
  void addAll(Iterable<String> wallpaperKeys) {
    final int before = _ids.length;
    _ids.addAll(wallpaperKeys);
    if (_ids.length != before) notifyListeners();
  }

  /// Leaves selection mode and drops every tick.
  void clear() {
    if (!_active && _ids.isEmpty) return;
    _active = false;
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

  /// Whether [wallpaperKey] is ticked on the shelf above [context].
  static bool isSelected(BuildContext context, String wallpaperKey) {
    return of(context)?.contains(wallpaperKey) ?? false;
  }
}

/// The wash-and-tick a selectable tile wears while its shelf is selecting.
///
/// Extracted so every shelf shows selection identically: `WallpaperTile` (the
/// browse, favorites and history shelves) and the private library's own tile
/// both draw this one widget, rather than each owning a copy that could drift —
/// which is exactly how the private tiles came to show no selection at all.
///
/// Draws nothing until the shelf above it is selecting, and an empty tick on
/// the untouched tiles once it is: that empty circle is what says the shelf
/// changed mode, so the first tap on an unticked tile does not read as "open".
/// Place it in an expanded [Stack] over the thumbnail — it fills the tile, and
/// sits in the top-left corner, the one the missing badge (top-right) and C4's
/// marks (bottom-right) leave free.
class WallpaperSelectionOverlay extends StatelessWidget {
  /// Draws the selection state of [wallpaperKey] on the shelf above it.
  const WallpaperSelectionOverlay({required this.wallpaperKey, super.key});

  /// The id whose ticked state this overlay reflects.
  final String wallpaperKey;

  @override
  Widget build(BuildContext context) {
    if (!WallpaperSelectionScope.isActive(context)) {
      return const SizedBox.shrink();
    }
    final bool selected = WallpaperSelectionScope.isSelected(
      context,
      wallpaperKey,
    );
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (selected) ColoredBox(color: colors.primary.withValues(alpha: 0.28)),
        Positioned(top: 6, left: 6, child: _tick(colors, selected)),
      ],
    );
  }

  Widget _tick(ColorScheme colors, bool selected) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // The same 0.82 the marks pill uses, and for the same reason: legible
        // over a wallpaper of any luminance.
        color: selected
            ? colors.primary
            : colors.surface.withValues(alpha: .82),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          selected ? Icons.check : Icons.radio_button_unchecked,
          size: 16,
          color: selected ? colors.onPrimary : colors.onSurfaceVariant,
        ),
      ),
    );
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
///   wallpaperKey: wallpaper.ref.key,
///   onOpen: () => _openDetail(context, loaded, index),
/// );
/// WallpaperTile(onTap: gestures.onTap, onLongPress: gestures.onLongPress);
/// ```
({VoidCallback onTap, VoidCallback? onLongPress}) selectableTileGestures({
  required BuildContext context,
  required String wallpaperKey,
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
          ? () => selection.selectOnly(wallpaperKey)
          : onLongPress,
    );
  }
  void tick() => selection.toggle(wallpaperKey);
  return (onTap: tick, onLongPress: tick);
}
