import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/download_queue_controller.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/move_to_private_action.dart';
import 'package:tela/app/pinned_download_tier.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/bulk_progress_dialog.dart';
import 'package:tela/core/ui/download_destination_dialog.dart';
import 'package:tela/core/ui/download_volume_sheet.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/ports/favorites_repository.dart';
import 'package:tela/domain/ports/settings_repository.dart';
import 'package:tela/domain/use_cases/delete_downloads.dart';
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

  /// Move every ticked download into the private library. Confirms first: the
  /// file leaves Photos, and tela cannot put it back there afterwards.
  moveToPrivate,
}

/// Whether [action] asks before it acts.
///
/// The two destructive ones do — [WallpaperBatchAction.forget] and
/// [WallpaperBatchAction.delete] — and so does
/// [WallpaperBatchAction.moveToPrivate], which deletes nothing but is not
/// undoable either: the file leaves Photos, and the private tier keeps no
/// record of what it holds, so tela can never prove the image safe enough to
/// put back. The rest are one tap from being undone by the opposite action, and
/// a confirmation on each would train the user to dismiss the one that matters.
bool wallpaperBatchActionConfirms(WallpaperBatchAction action) =>
    action == WallpaperBatchAction.forget ||
    action == WallpaperBatchAction.delete ||
    action == WallpaperBatchAction.moveToPrivate;

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
      return _deleteAll(context, ref, wallpapers, messenger, l10n);
    case WallpaperBatchAction.moveToPrivate:
      return _moveAllToPrivate(context, ref, wallpapers);
  }
}

/// Moves every ticked download into the private library.
///
/// Reads the records from the history listing for the same reason
/// [_deleteAll] does: a move needs each file's tier and location, not just its
/// id. The confirmation and the tally live in `confirmAndMoveToPrivate`, which
/// the viewers and the detail screen share — a batch here is that action at a
/// count of many, and its confirmation has **already been shown** by
/// [runWallpaperBatchAction], so this branch must not ask twice.
Future<bool> _moveAllToPrivate(
  BuildContext context,
  WidgetRef ref,
  List<Wallpaper> wallpapers,
) async {
  final List<DownloadRecord> records = await _recordsFor(ref, wallpapers);
  if (!context.mounted) return true;
  await moveToPrivate(context: context, ref: ref, records: records);
  return true;
}

/// Hard-deletes every ticked download — files and rows — through the one bulk
/// use case, so the gallery tier resolves to a single system prompt.
///
/// Reports the honest tally: a declined prompt or a failed delete leaves that
/// subset, and "deleted 3 of 5" is a different fact than "deleted 5". Reads the
/// records from the history listing, since a hard delete needs each file's tier
/// and location, not just its id.
///
/// Shows its progress while it runs: a selection of hundreds takes long enough
/// that a silent screen reads as a broken button (owner, 2026-07-28).
Future<bool> _deleteAll(
  BuildContext context,
  WidgetRef ref,
  List<Wallpaper> wallpapers,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
) async {
  final List<DownloadRecord> records = await _recordsFor(ref, wallpapers);
  if (!context.mounted) return true;
  final int deleted = await showBulkProgress<int>(
    context: context,
    label: (int done, int total) => l10n.batchDeleteProgress(done, total),
    work: (DeletionProgress report) =>
        ref.read(deleteDownloadsProvider)(records, onProgress: report),
  );
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
  final Map<String, DownloadRecord> byKey = <String, DownloadRecord>{
    for (final DownloadRecord record in recent)
      record.wallpaper.ref.key: record,
  };
  return <DownloadRecord>[
    for (final Wallpaper wallpaper in wallpapers)
      if (byKey[wallpaper.ref.key] case final DownloadRecord record) record,
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
    await favorites.forget(wallpaper.ref);
  }
  _refreshFavorites(ref, wallpapers);
}

/// Invalidates once for the listing and once per id, since `refreshFavorites`
/// is per-wallpaper — the family entry `isFavoriteProvider(id)` is what the
/// detail screen's heart reads, and a batch that skipped it would leave a
/// hearted detail screen behind an unfavorited grid.
void _refreshFavorites(WidgetRef ref, List<Wallpaper> wallpapers) {
  for (final Wallpaper wallpaper in wallpapers) {
    refreshFavorites(ref, wallpaper.ref);
  }
}

/// Puts the whole selection in the download queue and says so.
///
/// **Queued, not downloaded here.** The loop this replaced awaited one
/// multi-megabyte original after another inside a widget callback, so a hundred
/// wallpapers took as long as a hundred sequential downloads and closing the
/// app lost every one that had not landed — its only record of what was still
/// owed was a stack frame. The queue is durable, drains three at a time, and
/// can be paused, retried and cancelled per item.
///
/// The destination is resolved and any first-time folder granted *before*
/// anything is enqueued: the worker drains with no screen mounted and cannot
/// answer a chooser.
///
/// The tally that used to be reported here — "downloaded 9 of 12" — moves to
/// the queue tab, which can be honest per wallpaper instead of in aggregate.
Future<bool> _downloadAll(
  BuildContext context,
  WidgetRef ref,
  List<Wallpaper> wallpapers,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
) async {
  // Captured before the first await, like the messenger above: the shelf can
  // be gone by the time the *View* action is tapped, and a GoRouter outlives
  // the widget that was asked for it.
  final GoRouter router = GoRouter.of(context);
  final ({bool proceed, StorageTier? tier}) destination =
      await _resolveBatchDestination(context, ref, wallpapers);
  if (!destination.proceed || !context.mounted) return false;
  final bool ready = await _ensureDownloadFolder(
    context,
    ref,
    wallpapers,
    destination.tier,
  );
  if (!ready) return false;

  final int queued = await ref
      .read(downloadQueueControllerProvider.notifier)
      .enqueue(wallpapers, tier: destination.tier);
  _sayQueued(router, messenger, l10n, queued, wallpapers.length);
  return true;
}

/// Grants the files-outside-gallery folder now, while there is still a screen
/// to ask on.
///
/// The queue worker deliberately cannot run the chooser — see
/// `DrainDownloadQueue` — so a batch that would land in that tier has to settle
/// first-time setup up front, or every entry fails on the same unanswered
/// question. False when the user backed out of the chooser: nothing is queued
/// and the selection stays, exactly as backing out of the old inline setup did.
///
/// A folder that is granted but *unreachable* — an ejected card — is not
/// checked here and is not meant to be: that failure needs an attempt to
/// discover, and the queue now has somewhere honest to report it, per entry,
/// with a retry beside it.
Future<bool> _ensureDownloadFolder(
  BuildContext context,
  WidgetRef ref,
  List<Wallpaper> wallpapers,
  StorageTier? tier,
) async {
  if (!await _landsOutsideGallery(ref, wallpapers, tier)) return true;
  if (!context.mounted) return false;
  return ref
      .read(configuredDownloadProvider)
      .ensureFolder(
        ({required bool offerSdCard}) =>
            chooseDownloadVolume(context, offerSdCard: offerSdCard),
      );
}

/// Whether any wallpaper in this batch is headed for the tier that owns a
/// folder.
///
/// A resolved [tier] answers it outright. A null one means "resolve per
/// wallpaper when it runs", so the same rule the download itself will apply is
/// applied here — [StorageSettings.tierWithPin], over the pin and each purity's
/// configured destination — rather than a second guess at it.
Future<bool> _landsOutsideGallery(
  WidgetRef ref,
  List<Wallpaper> wallpapers,
  StorageTier? tier,
) async {
  if (tier != null) return tier == StorageTier.filesOutsideGallery;
  final SettingsRepository settings = ref.read(settingsRepositoryProvider);
  final StorageTier? pin = await ref.read(pinnedDownloadTierProvider.future);
  final StorageSettings storage = await settings.loadStorageSettings();
  return wallpapers.any(
    (Wallpaper wallpaper) =>
        storage.tierWithPin(wallpaper.purity, pin) ==
        StorageTier.filesOutsideGallery,
  );
}

/// Says how many went into the queue, with a way to go and watch them.
///
/// Reports the *newly* queued count when it differs, because re-ticking a shelf
/// whose wallpapers are already waiting queues nothing new, and "queued 12"
/// over a queue that did not grow is the same kind of lie the old aggregate
/// tally was.
void _sayQueued(
  GoRouter router,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  int queued,
  int total,
) {
  final String message = queued == total
      ? l10n.batchDownloadQueued(total)
      : l10n.batchDownloadQueuedPartial(queued, total);
  _say(
    messenger,
    message,
    action: SnackBarAction(
      label: l10n.batchDownloadQueuedView,
      onPressed: () => router.pushNamed(TelaRoutes.downloadHistoryName),
    ),
  );
}

/// Where a whole batch lands: the one destination the user picks from the
/// intersection chooser. A dismissed chooser answers `proceed: false` so the
/// batch abandons and the selection stays.
///
/// **A batch always asks. Nothing silences it — not even the pin.**
///
/// This has moved twice, and the reasoning is worth keeping. It first asked
/// only when the selection held a not-safe wallpaper, on the grounds that the
/// chooser existed for the destination a not-safe download must not enter
/// unasked; that left "put these thirty in my files folder" with no way to say
/// it at all. Then it asked unless a pin was set, since silencing the question
/// is exactly what "Keep sending here" means.
///
/// That second rule was wrong **here**, for a reason single downloads do not
/// share. A pin earns its keep by removing a question from a one-tap action you
/// perform constantly. A batch is neither: it is deliberate, it is rare, and it
/// commits many multi-megabyte files at once. Silencing it turned a pin the
/// user may have set weeks ago on a single wallpaper into an invisible standing
/// order over every future selection — which is precisely how it presented on
/// the device (owner, 2026-07-27: "when I batch download it's not asking where
/// I want it").
///
/// The pin is not ignored: it is handed to the chooser, which shows it,
/// starts its switch on, and offers **Stop**. One tap on the pinned destination
/// is the same download it would have made silently — the difference is that
/// the user can see what it is about to do, and change it.
Future<({bool proceed, StorageTier? tier})> _resolveBatchDestination(
  BuildContext context,
  WidgetRef ref,
  List<Wallpaper> wallpapers,
) async {
  final StorageTier? pin = await ref.read(pinnedDownloadTierProvider.future);
  final Set<Purity> purities = wallpapers
      .map((Wallpaper wallpaper) => wallpaper.purity)
      .toSet();
  if (!context.mounted) return (proceed: false, tier: null);
  final DownloadDestinationChoice? choice =
      await chooseBatchDownloadDestination(
        context,
        purities: purities,
        count: wallpapers.length,
        pinnedTier: pin,
      );
  if (choice == null) return (proceed: false, tier: null);
  // Stop clears the pin and downloads nothing — the deliberate way out, and the
  // same contract the single chooser honours. Answering `proceed: false`
  // without clearing would leave the button doing nothing at all.
  if (choice.stopsPin) {
    await ref.read(pinnedDownloadTierProvider.notifier).clear();
    return (proceed: false, tier: null);
  }
  if (choice.pin) {
    await ref.read(pinnedDownloadTierProvider.notifier).pin(choice.tier!);
  }
  return (proceed: true, tier: choice.tier);
}

Future<void> _forgetAll(WidgetRef ref, List<Wallpaper> wallpapers) async {
  for (final Wallpaper wallpaper in wallpapers) {
    await ref.read(downloadHistoryProvider).forget(wallpaper.ref);
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
  final ({String title, String body, String confirm}) words = _confirmWords(
    l10n,
    action,
    count,
  );
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(words.title),
      content: Text(words.body),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(words.confirm),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// The three sentences one confirming action needs, per action.
///
/// A switch and not a chain of ternaries: there are three of these now, and the
/// wording *is* the feature — a reader has to be able to see at a glance which
/// promise each one makes.
({String title, String body, String confirm}) _confirmWords(
  AppLocalizations l10n,
  WallpaperBatchAction action,
  int count,
) {
  return switch (action) {
    WallpaperBatchAction.delete => (
      title: l10n.batchDeleteTitle(count),
      body: l10n.batchDeleteBody(count),
      confirm: l10n.downloadDelete,
    ),
    WallpaperBatchAction.moveToPrivate => (
      title: l10n.moveToPrivateTitle(count),
      body: l10n.moveToPrivateBody(count),
      confirm: l10n.moveToPrivateAction,
    ),
    _ => (
      title: l10n.batchForgetTitle(count),
      body: l10n.batchForgetBody(count),
      confirm: l10n.downloadHistoryForget,
    ),
  };
}

void _say(
  ScaffoldMessengerState messenger,
  String message, {
  ToastKind kind = ToastKind.success,
  SnackBarAction? action,
}) {
  showTelaToast(messenger, message, kind: kind, action: action);
}
