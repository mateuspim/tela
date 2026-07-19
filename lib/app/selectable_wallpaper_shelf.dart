import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/wallpaper_batch_actions.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/selection_shelf.dart';
import 'package:tela/domain/models/wallpaper.dart';

/// A wallpaper shelf whose tiles can be ticked and acted on in a batch.
///
/// Maps [WallpaperBatchAction]s onto the domain-free [SelectionAction]s the
/// shared bar understands, and nothing else — the selection itself, the bar,
/// the back handling and *select all* all live in `SelectionShelfScope` /
/// `SelectionShelf`, which the private library reuses with its own actions.
///
/// The scope is **not** created here. It has to sit above the screen's
/// `Scaffold` so an app-bar *Select* button can reach it, so each screen wraps
/// itself; this only renders the bar where the shelf is.
///
/// ```dart
/// SelectableWallpaperShelf(
///   wallpapers: saved,
///   actions: const <WallpaperBatchAction>[WallpaperBatchAction.unfavorite],
///   child: grid,
/// );
/// ```
class SelectableWallpaperShelf extends ConsumerWidget {
  /// Wraps [child], batching over [wallpapers] with [actions].
  const SelectableWallpaperShelf({
    required this.wallpapers,
    required this.actions,
    required this.child,
    super.key,
  });

  /// Every wallpaper the shelf is showing, in the order it shows them.
  final List<Wallpaper> wallpapers;

  /// The batch actions this shelf offers, left to right in the bar.
  final List<WallpaperBatchAction> actions;

  /// The shelf itself — normally a `JustifiedWallpaperGrid`.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SelectionShelf(
      itemIds: <String>[for (final Wallpaper w in wallpapers) w.id],
      actions: <SelectionAction>[
        for (final WallpaperBatchAction action in actions)
          _actionFor(context, ref, l10n, action),
      ],
      child: child,
    );
  }

  SelectionAction _actionFor(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    WallpaperBatchAction action,
  ) {
    return SelectionAction(
      icon: _iconOf(action),
      label: _labelOf(l10n, action),
      run: (List<String> ids) => runWallpaperBatchAction(
        context: context,
        ref: ref,
        action: action,
        wallpapers: _selected(ids),
      ),
    );
  }

  /// The ticked wallpapers, in shelf order.
  ///
  /// Resolved from the shelf's own list rather than held in the selection: the
  /// listing is the authority on what is on screen, so an id whose wallpaper
  /// has since gone is dropped instead of acted on as a stale copy.
  List<Wallpaper> _selected(List<String> ids) {
    final Set<String> ticked = ids.toSet();
    return <Wallpaper>[
      for (final Wallpaper w in wallpapers)
        if (ticked.contains(w.id)) w,
    ];
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
