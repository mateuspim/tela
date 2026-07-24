import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/configured_download.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/download_destination_dialog.dart';
import 'package:tela/core/ui/download_volume_sheet.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/ports/favorites_repository.dart';
import 'package:tela/domain/ports/settings_repository.dart';
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

  /// Hard-delete every ticked download — the files and their rows. Destructive;
  /// confirms first, and batches the gallery tier into one system prompt.
  delete,
}

/// Whether [action] asks before it acts.
///
/// The two destructive ones do — [WallpaperBatchAction.forget] and
/// [WallpaperBatchAction.delete]. The others are one tap from being undone by
/// the opposite action, and a confirmation on each would train the user to
/// dismiss the one that matters.
bool wallpaperBatchActionConfirms(WallpaperBatchAction action) =>
    action == WallpaperBatchAction.forget ||
    action == WallpaperBatchAction.delete;

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
    final bool confirmed = await _confirmDestructive(
      context,
      action,
      wallpapers.length,
    );
    if (!confirmed || !context.mounted) return false;
  }
  // Read before the first await: every branch reports across an async gap, and
  // a batch of downloads is long enough that the shelf may be gone by then.
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final AppLocalizations l10n = AppLocalizations.of(context);
  return _perform(context, ref, action, wallpapers, messenger, l10n);
}

/// Runs the action and reports whether it ran — false only when the download
/// chooser was dismissed before anything was written, so the caller keeps a
/// selection the user did not abandon.
Future<bool> _perform(
  BuildContext context,
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
      return true;
    case WallpaperBatchAction.unfavorite:
      await _unfavoriteAll(ref, wallpapers);
      _say(messenger, l10n.batchUnfavoriteDone(wallpapers.length));
      return true;
    case WallpaperBatchAction.download:
      return _downloadAll(context, ref, wallpapers, messenger, l10n);
    case WallpaperBatchAction.forget:
      await _forgetAll(ref, wallpapers);
      _say(messenger, l10n.batchForgetDone(wallpapers.length));
      return true;
    case WallpaperBatchAction.delete:
      return _deleteAll(ref, wallpapers, messenger, l10n);
  }
}

/// Hard-deletes every ticked download — files and rows — through the one bulk
/// use case, so the gallery tier resolves to a single system prompt.
///
/// Reports the honest tally: a declined prompt or a failed delete leaves that
/// subset, and "deleted 3 of 5" is a different fact than "deleted 5". Reads the
/// records from the history listing, since a hard delete needs each file's tier
/// and location, not just its id.
Future<bool> _deleteAll(
  WidgetRef ref,
  List<Wallpaper> wallpapers,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
) async {
  final List<DownloadRecord> records = await _recordsFor(ref, wallpapers);
  final int deleted = await ref.read(deleteDownloadsProvider)(records);
  refreshDownloads(ref);
  _sayDeleteOutcome(messenger, l10n, deleted, wallpapers.length);
  return true;
}

/// The history records for [wallpapers], in the selection's order, dropping any
/// whose row has since left the listing.
Future<List<DownloadRecord>> _recordsFor(
  WidgetRef ref,
  List<Wallpaper> wallpapers,
) async {
  final List<DownloadRecord> recent = await ref.read(
    recentDownloadsProvider.future,
  );
  final Map<String, DownloadRecord> byId = <String, DownloadRecord>{
    for (final DownloadRecord record in recent) record.wallpaper.id: record,
  };
  return <DownloadRecord>[
    for (final Wallpaper wallpaper in wallpapers)
      if (byId[wallpaper.id] case final DownloadRecord record) record,
  ];
}

void _sayDeleteOutcome(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  int deleted,
  int total,
) {
  if (deleted == total) {
    _say(messenger, l10n.batchDeleteDone(total));
    return;
  }
  _say(
    messenger,
    l10n.batchDeletePartial(deleted, total, total - deleted),
    // Some are still on the device — a declined prompt, or a failure — and that
    // is the outcome the user may need to act on, so no success tick.
    kind: ToastKind.failure,
  );
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
Future<bool> _downloadAll(
  BuildContext context,
  WidgetRef ref,
  List<Wallpaper> wallpapers,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
) async {
  final ({bool proceed, StorageTier? tier}) destination =
      await _resolveBatchDestination(context, ref, wallpapers);
  if (!destination.proceed) return false;

  int saved = 0;
  for (final Wallpaper wallpaper in wallpapers) {
    final DownloadOutcome outcome = await ref.read(configuredDownloadProvider)(
      wallpaper,
      chooseVolume: ({required bool offerSdCard}) =>
          chooseDownloadVolume(context, offerSdCard: offerSdCard),
      tier: destination.tier,
    );
    // Backing out of first-time folder setup abandons the batch: every
    // remaining download would ask the same unanswered question.
    if (outcome == DownloadOutcome.cancelled) break;
    // An unavailable folder is the same wall for every wallpaper left, so stop
    // and name it — a "0 of N" tally would hide why nothing saved.
    if (outcome == DownloadOutcome.folderUnavailable) {
      refreshDownloads(ref);
      _say(
        messenger,
        l10n.detailDownloadFolderUnavailable,
        kind: ToastKind.failure,
      );
      return true;
    }
    if (outcome == DownloadOutcome.saved) saved++;
  }
  refreshDownloads(ref);
  _sayDownloadOutcome(messenger, l10n, saved, wallpapers.length);
  return true;
}

/// Where a whole batch lands: the pin when one is set (each item resolves it,
/// invariant permitting, via a null tier), or the one destination the user
/// picks from the intersection chooser. A dismissed chooser answers
/// `proceed: false` so the batch abandons and the selection stays.
Future<({bool proceed, StorageTier? tier})> _resolveBatchDestination(
  BuildContext context,
  WidgetRef ref,
  List<Wallpaper> wallpapers,
) async {
  final SettingsRepository settings = ref.read(settingsRepositoryProvider);
  // A pin governs the batch too: hand each download a null tier and let the
  // download use case send it to the pin, dropping explicit items to their
  // private tier where a gallery pin cannot hold them.
  if (await settings.loadPinnedDownloadTier() != null) {
    return (proceed: true, tier: null);
  }
  final Set<Purity> purities = wallpapers
      .map((Wallpaper wallpaper) => wallpaper.purity)
      .toSet();
  // A wholly-safe batch routes silently, the same rule a single safe tap
  // follows: the chooser is for the destination a not-safe download must not
  // enter unasked. Nothing here is not-safe, so there is nothing to decide.
  if (!purities.any((Purity purity) => purity != Purity.sfw)) {
    return (proceed: true, tier: null);
  }
  if (!context.mounted) return (proceed: false, tier: null);
  final DownloadDestinationChoice? choice =
      await chooseBatchDownloadDestination(
        context,
        purities: purities,
        count: wallpapers.length,
      );
  if (choice == null || choice.stopsPin) return (proceed: false, tier: null);
  if (choice.pin) await settings.setPinnedDownloadTier(choice.tier);
  return (proceed: true, tier: choice.tier);
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
  _say(
    messenger,
    l10n.batchDownloadPartial(saved, total, total - saved),
    // Some of them are not on the device. That is the one batch outcome the
    // user has to act on, so it does not get a success tick.
    kind: ToastKind.failure,
  );
}

Future<void> _forgetAll(WidgetRef ref, List<Wallpaper> wallpapers) async {
  for (final Wallpaper wallpaper in wallpapers) {
    await ref.read(downloadHistoryProvider).forget(wallpaper.id);
  }
  ref.invalidate(recentDownloadsProvider);
}

/// Says what will and will not happen, in the plural.
///
/// The wording is the feature. For *forget*, these tiles look like files and a
/// button reading "Remove" over nine of them is the moment a user most needs
/// telling their downloads are staying put; for *delete*, it is the opposite
/// promise — the files really are going — and the copy has to be as plain about
/// that as the single-row confirm is.
Future<bool> _confirmDestructive(
  BuildContext context,
  WallpaperBatchAction action,
  int count,
) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final bool deleting = action == WallpaperBatchAction.delete;
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(
        deleting ? l10n.batchDeleteTitle(count) : l10n.batchForgetTitle(count),
      ),
      content: Text(
        deleting ? l10n.batchDeleteBody(count) : l10n.batchForgetBody(count),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            deleting ? l10n.downloadDelete : l10n.downloadHistoryForget,
          ),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

void _say(
  ScaffoldMessengerState messenger,
  String message, {
  ToastKind kind = ToastKind.success,
}) {
  showTelaToast(messenger, message, kind: kind);
}
