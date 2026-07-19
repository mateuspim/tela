import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_target_sheet.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/features/favorites/favorites_providers.dart';

/// What a long press on a wall tile offers, without opening the wallpaper.
///
/// Collecting used to cost a full round trip through the detail screen for
/// every wallpaper, which on a seven-tiles-per-row tablet wall is the slowest
/// part of it. Sharing is deliberately absent: it is the one action with a
/// purity rule attached (`shareOptionsFor`), and a menu that has to grow a
/// condition is the wrong place to offer it — the detail screen still does.
enum WallpaperQuickAction {
  /// Add the wallpaper to favorites, or take it back out.
  favorite,

  /// Download to the destination configured for the wallpaper's purity.
  download,

  /// Apply it to a chosen Android surface.
  setWallpaper,

  /// Give up on the shortcut and open the wallpaper properly.
  openDetail,
}

/// Asks what to do with the long-pressed [wallpaper]; null when dismissed.
///
/// The caller runs the answer ([runWallpaperQuickAction]) rather than the sheet
/// running it itself, because every action outlives the sheet: the target
/// chooser and the result snackbar both need a context that is still mounted
/// once this one has popped.
///
/// ```dart
/// final WallpaperQuickAction? action =
///     await chooseWallpaperQuickAction(context, wallpaper);
/// ```
Future<WallpaperQuickAction?> chooseWallpaperQuickAction(
  BuildContext context,
  Wallpaper wallpaper,
) {
  return showModalBottomSheet<WallpaperQuickAction>(
    context: context,
    builder: (BuildContext context) => _QuickActionSheet(wallpaper: wallpaper),
  );
}

/// Performs [action] on [wallpaper], reporting the outcome over [context].
///
/// [openDetail] is the caller's own navigation rather than a push from here:
/// the wall opens its detail screen on a gallery *session* seeded at the
/// pressed index, and only the grid knows the listing that session walks.
Future<void> runWallpaperQuickAction({
  required BuildContext context,
  required WidgetRef ref,
  required Wallpaper wallpaper,
  required WallpaperQuickAction action,
  required VoidCallback openDetail,
}) async {
  switch (action) {
    case WallpaperQuickAction.favorite:
      await _toggleFavorite(ref, wallpaper);
    case WallpaperQuickAction.download:
      await _download(context, ref, wallpaper);
    case WallpaperQuickAction.setWallpaper:
      await _setWallpaper(context, ref, wallpaper);
    case WallpaperQuickAction.openDetail:
      openDetail();
  }
}

/// Deliberately silent: the tile's own corner mark appears or disappears under
/// the user's finger, which says it better than a snackbar over the wall would.
Future<void> _toggleFavorite(WidgetRef ref, Wallpaper wallpaper) async {
  await ref.read(toggleFavoriteProvider)(wallpaper);
  refreshFavorites(ref, wallpaper.id);
}

Future<void> _download(
  BuildContext context,
  WidgetRef ref,
  Wallpaper wallpaper,
) async {
  // Read before the await, not after: the snackbar is shown across an async gap
  // and the wall may have been navigated away from by then.
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final AppLocalizations l10n = AppLocalizations.of(context);
  try {
    await ref.read(downloadWallpaperProvider)(wallpaper);
    refreshDownloads(ref);
    _say(messenger, l10n.detailDownloadSuccess);
  } on ImageStoreFailure {
    _say(messenger, l10n.detailDownloadFailure);
  }
}

/// Asks Home/Lock/Both first, through the same chooser the detail screen and
/// the download history use, so the question reads identically everywhere.
Future<void> _setWallpaper(
  BuildContext context,
  WidgetRef ref,
  Wallpaper wallpaper,
) async {
  final WallpaperTarget? target = await chooseWallpaperTarget(context);
  if (target == null || !context.mounted) return;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final AppLocalizations l10n = AppLocalizations.of(context);
  try {
    await ref.read(applyWallpaperProvider)(wallpaper, target);
    _say(messenger, l10n.detailApplySuccess);
  } on WallpaperApplyFailure {
    _say(messenger, l10n.detailApplyFailure);
  }
}

void _say(ScaffoldMessengerState messenger, String message) {
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

class _QuickActionSheet extends ConsumerWidget {
  const _QuickActionSheet({required this.wallpaper});

  final Wallpaper wallpaper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // An unresolved read draws the empty heart rather than a spinner, for the
    // reason `FavoriteButton` gives: the answer is one local SQLite round trip
    // away, and a flicker of progress in a menu row reads worse than an outline
    // that fills in.
    final bool isFavorite =
        ref.watch(isFavoriteProvider(wallpaper.id)).value ?? false;
    // Scrolls rather than clips. A modal sheet is capped at a fraction of the
    // screen, and five rows do not fit that cap on a short viewport — a phone
    // in landscape, or the 800x600 the widget tests run at, where this first
    // showed up as a 31px overflow. The column still sizes to its content, so
    // nothing scrolls where everything fits.
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // The wallpaper's id, the same label the detail screen uses. It
            // says *something* is selected, but on the device (2026-07-19) it
            // reads as a bare "Wallpaper k8lvqm" — which cannot tell you the
            // long press landed on the tile you aimed at, because nobody
            // recognises a wallhaven id by eye. A thumbnail here would; left
            // as a follow-up rather than widened into this slice.
            ListTile(title: Text(l10n.detailPreviewLabel(wallpaper.id))),
            _tile(
              context,
              isFavorite ? Icons.favorite : Icons.favorite_border,
              isFavorite ? l10n.favoriteRemove : l10n.favoriteAdd,
              WallpaperQuickAction.favorite,
            ),
            _tile(
              context,
              Icons.download_outlined,
              l10n.detailDownload,
              WallpaperQuickAction.download,
            ),
            _tile(
              context,
              Icons.wallpaper_outlined,
              l10n.detailSetWallpaper,
              WallpaperQuickAction.setWallpaper,
            ),
            _tile(
              context,
              Icons.info_outline,
              l10n.quickActionOpenDetail,
              WallpaperQuickAction.openDetail,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String label,
    WallpaperQuickAction action,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () => Navigator.pop(context, action),
    );
  }
}
