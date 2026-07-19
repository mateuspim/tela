import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/wallpaper_batch_actions.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_selection.dart';
import 'package:tela/domain/models/wallpaper.dart';

/// Wraps one shelf so its tiles can be ticked and acted on in a batch.
///
/// Owns the [WallpaperSelection], publishes it to the tiles below, and draws
/// the contextual bar while anything is ticked. Every wallpaper shelf gets its
/// selection from here rather than growing its own, which is the same argument
/// `TileDensityScope` and `WallpaperMarksScope` settled: one wiring point is
/// what keeps four shelves behaving identically.
///
/// The bar is a band **above** the grid rather than a floating bottom bar or a
/// swapped app bar. Two of these shelves are embedded widgets with no app bar
/// of their own (the favorites grid, the browse wall), and two sit above a
/// bottom navigation bar a floating bar would fight, so the band is the one
/// position that works in all four without each shelf special-casing itself.
///
/// ```dart
/// SelectableWallpaperShelf(
///   wallpapers: saved,
///   actions: const <WallpaperBatchAction>[WallpaperBatchAction.unfavorite],
///   child: grid,
/// );
/// ```
class SelectableWallpaperShelf extends ConsumerStatefulWidget {
  /// Wraps [child], batching over [wallpapers] with [actions].
  const SelectableWallpaperShelf({
    required this.wallpapers,
    required this.actions,
    required this.child,
    super.key,
  });

  /// Every wallpaper the shelf is currently showing, in the order it shows
  /// them. Selection is resolved against this list, so an id that scrolls out
  /// of a listing or is removed by a batch simply stops being selected.
  final List<Wallpaper> wallpapers;

  /// The batch actions this shelf offers, left to right in the bar.
  final List<WallpaperBatchAction> actions;

  /// The shelf itself — normally a `JustifiedWallpaperGrid`.
  final Widget child;

  @override
  ConsumerState<SelectableWallpaperShelf> createState() =>
      _SelectableWallpaperShelfState();
}

class _SelectableWallpaperShelfState
    extends ConsumerState<SelectableWallpaperShelf> {
  final WallpaperSelection _selection = WallpaperSelection();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WallpaperSelectionScope(
      selection: _selection,
      // Back leaves selection mode before it leaves the screen. Without this a
      // user who ticked nine wallpapers and reached for Back to undo it loses
      // the shelf instead, which is the one gesture everyone tries first.
      child: ListenableBuilder(
        listenable: _selection,
        builder: (BuildContext context, Widget? child) => PopScope(
          canPop: !_selection.isActive,
          onPopInvokedWithResult: _leaveSelectionInsteadOfPopping,
          child: Column(
            children: <Widget>[
              if (_selection.isActive) _bar(context),
              Expanded(child: child!),
            ],
          ),
        ),
        child: widget.child,
      ),
    );
  }

  void _leaveSelectionInsteadOfPopping(bool didPop, Object? result) {
    if (!didPop) _selection.clear();
  }

  /// The contextual bar: what is ticked, and what can be done to it.
  Widget _bar(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.batchCancel,
              onPressed: _selection.clear,
            ),
            Expanded(child: Text(l10n.batchSelectedCount(_selection.count))),
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: l10n.batchSelectAll,
              onPressed: _selectAll,
            ),
            for (final WallpaperBatchAction action in widget.actions)
              _action(context, l10n, action),
          ],
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context,
    AppLocalizations l10n,
    WallpaperBatchAction action,
  ) {
    return IconButton(
      icon: Icon(_iconOf(action)),
      tooltip: _labelOf(l10n, action),
      onPressed: () => unawaited(_run(action)),
    );
  }

  void _selectAll() {
    _selection.addAll(widget.wallpapers.map((Wallpaper w) => w.id));
  }

  /// Runs [action] over the ticked wallpapers, then leaves selection mode.
  ///
  /// Resolves the ids against the shelf's current list rather than holding
  /// [Wallpaper]s in the selection: the listing is the authority on what is on
  /// screen, and this drops an id whose wallpaper has since gone rather than
  /// acting on a stale copy of it.
  ///
  /// Only clears when the batch actually ran — a declined *forget* confirmation
  /// leaves every tick exactly where it was, since the user cancelled the
  /// action, not the selection.
  Future<void> _run(WallpaperBatchAction action) async {
    final List<Wallpaper> selected = widget.wallpapers
        .where((Wallpaper w) => _selection.contains(w.id))
        .toList();
    final bool ran = await runWallpaperBatchAction(
      context: context,
      ref: ref,
      action: action,
      wallpapers: selected,
    );
    if (ran) _selection.clear();
  }

  IconData _iconOf(WallpaperBatchAction action) => switch (action) {
    WallpaperBatchAction.favorite => Icons.favorite_border,
    WallpaperBatchAction.unfavorite => Icons.heart_broken_outlined,
    WallpaperBatchAction.download => Icons.download_outlined,
    WallpaperBatchAction.forget => Icons.playlist_remove,
  };

  String _labelOf(AppLocalizations l10n, WallpaperBatchAction action) =>
      switch (action) {
        WallpaperBatchAction.favorite => l10n.favoriteAdd,
        WallpaperBatchAction.unfavorite => l10n.favoriteRemove,
        WallpaperBatchAction.download => l10n.detailDownload,
        WallpaperBatchAction.forget => l10n.downloadHistoryForgetMenu,
      };
}
