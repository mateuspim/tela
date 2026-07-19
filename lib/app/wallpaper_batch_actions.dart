import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/ports/favorites_repository.dart';
import 'package:tela/features/favorites/favorites_providers.dart';

/// What a shelf can do to every ticked wallpaper at once.
///
/// Each shelf offers only the subset that says something there, the same way
/// `visibleMarks` narrows C4's tile marks: offering *Add to favorites* on the
/// favorites shelf is a button that cannot change anything.
///
/// Setting a wallpaper is deliberately absent, and unlike the quick sheet's
/// missing *Share* it is not a purity question — "apply these nine wallpapers"
/// has no meaning at all, because the device has one wallpaper.
enum WallpaperBatchAction {
  /// Save every ticked wallpaper to favorites.
  favorite,

  /// Drop every ticked wallpaper from favorites.
  unfavorite,

  /// Download every ticked wallpaper to its purity's configured destination.
  download,

  /// Forget every ticked download-history row. Destructive; confirms first.
  forget,
}

/// Whether [action] asks before it acts.
///
/// Only [WallpaperBatchAction.forget] does. The other three are one tap from
/// being undone by the opposite action, and a confirmation on each would train
/// the user to dismiss the one that matters.
bool wallpaperBatchActionConfirms(WallpaperBatchAction action) =>
    action == WallpaperBatchAction.forget;

/// Performs [action] on every wallpaper in [wallpapers], reporting the outcome.
///
/// Returns whether the batch ran — false when a confirmation was declined, so
/// the caller can leave the ticks in place rather than dropping a selection the
/// user did not abandon.
///
/// ```dart
/// final bool ran = await runWallpaperBatchAction(
///   context: context,
///   ref: ref,
///   action: WallpaperBatchAction.download,
///   wallpapers: selected,
/// );
/// ```
Future<bool> runWallpaperBatchAction({
  required BuildContext context,
  required WidgetRef ref,
  required WallpaperBatchAction action,
  required List<Wallpaper> wallpapers,
}) async {
  if (wallpapers.isEmpty) return false;
  if (wallpaperBatchActionConfirms(action)) {
    final bool confirmed = await _confirmForget(context, wallpapers.length);
    if (!confirmed || !context.mounted) return false;
  }
  // Read before the first await: every branch reports across an async gap, and
  // a batch of downloads is long enough that the shelf may be gone by then.
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final AppLocalizations l10n = AppLocalizations.of(context);
  await _perform(ref, action, wallpapers, messenger, l10n);
  return true;
}

Future<void> _perform(
  WidgetRef ref,
  WallpaperBatchAction action,
  List<Wallpaper> wallpapers,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
) async {
  switch (action) {
    case WallpaperBatchAction.favorite:
      await _favoriteAll(ref, wallpapers);
      _say(messenger, l10n.batchFavoriteDone(wallpapers.length));
    case WallpaperBatchAction.unfavorite:
      await _unfavoriteAll(ref, wallpapers);
      _say(messenger, l10n.batchUnfavoriteDone(wallpapers.length));
    case WallpaperBatchAction.download:
      await _downloadAll(ref, wallpapers, messenger, l10n);
    case WallpaperBatchAction.forget:
      await _forgetAll(ref, wallpapers);
      _say(messenger, l10n.batchForgetDone(wallpapers.length));
  }
}

/// Writes through the repository's [FavoritesRepository.save], **not** through
/// `ToggleFavorite`.
///
/// Load-bearing: toggling a mixed selection would un-favorite exactly the
/// wallpapers the user could see were already hearted, so "add these to
/// favorites" would remove some of them. `save` and `forget` are idempotent, so
/// a batch lands on the state the button's label promised regardless of where
/// each wallpaper started.
Future<void> _favoriteAll(WidgetRef ref, List<Wallpaper> wallpapers) async {
  final FavoritesRepository favorites = ref.read(favoritesRepositoryProvider);
  for (final Wallpaper wallpaper in wallpapers) {
    await favorites.save(wallpaper);
  }
  _refreshFavorites(ref, wallpapers);
}

Future<void> _unfavoriteAll(WidgetRef ref, List<Wallpaper> wallpapers) async {
  final FavoritesRepository favorites = ref.read(favoritesRepositoryProvider);
  for (final Wallpaper wallpaper in wallpapers) {
    await favorites.forget(wallpaper.id);
  }
  _refreshFavorites(ref, wallpapers);
}

/// Invalidates once for the listing and once per id, since `refreshFavorites`
/// is per-wallpaper — the family entry `isFavoriteProvider(id)` is what the
/// detail screen's heart reads, and a batch that skipped it would leave a
/// hearted detail screen behind an unfavorited grid.
void _refreshFavorites(WidgetRef ref, List<Wallpaper> wallpapers) {
  for (final Wallpaper wallpaper in wallpapers) {
    refreshFavorites(ref, wallpaper.id);
  }
}

/// Downloads **one at a time**, and reports the failures rather than hiding
/// them.
///
/// Sequential on purpose: these are multi-megabyte originals, and firing twenty
/// at once would hold twenty of them in flight for a wall the user selected in
/// two seconds. It also keeps the failure count honest — a partial batch says
/// so, because "downloaded 9 of 12" and "downloaded 12" are different outcomes
/// and a snackbar that rounds the first up to the second is a lie about what is
/// on the device.
Future<void> _downloadAll(
  WidgetRef ref,
  List<Wallpaper> wallpapers,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
) async {
  int saved = 0;
  for (final Wallpaper wallpaper in wallpapers) {
    try {
      await ref.read(downloadWallpaperProvider)(wallpaper);
      saved++;
    } on ImageStoreFailure {
      continue;
    }
  }
  refreshDownloads(ref);
  _sayDownloadOutcome(messenger, l10n, saved, wallpapers.length);
}

void _sayDownloadOutcome(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  int saved,
  int total,
) {
  if (saved == total) {
    _say(messenger, l10n.batchDownloadDone(total));
    return;
  }
  _say(messenger, l10n.batchDownloadPartial(saved, total, total - saved));
}

Future<void> _forgetAll(WidgetRef ref, List<Wallpaper> wallpapers) async {
  for (final Wallpaper wallpaper in wallpapers) {
    await ref.read(downloadHistoryProvider).forget(wallpaper.id);
  }
  ref.invalidate(recentDownloadsProvider);
}

/// Says what will and will not happen, in the plural.
///
/// The wording is the feature, exactly as it is for the single-row confirm this
/// mirrors: these tiles look like files, and a batch button reading "Remove"
/// over nine of them is the moment a user most needs telling that their
/// downloads are staying put.
Future<bool> _confirmForget(BuildContext context, int count) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(l10n.batchForgetTitle(count)),
      content: Text(l10n.batchForgetBody(count)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.downloadHistoryForget),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

void _say(ScaffoldMessengerState messenger, String message) {
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
