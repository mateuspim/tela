import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/batch_download_queueing.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/move_to_private_action.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/retag_downloads_action.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/bulk_progress_dialog.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/favorites_repository.dart';
import 'package:tela/domain/use_cases/delete_downloads.dart';
import 'package:tela/domain/use_cases/resolve_beam_files.dart';
import 'package:tela/features/beam/beam_sheet.dart';
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

  /// Send every ticked download to a machine on the local network.
  ///
  /// **Not gated, unlike the private library's beam.** The gate is about
  /// *explicit* content, not about the feature: safe and sketchy wallpapers
  /// beam freely, and `BeamWallpapers` refuses a batch holding an explicit one
  /// while the setting is off. Gating the action here too would have made the
  /// whole feature unreachable for the case it exists for.
  beam,

  /// Refile every ticked download under another tag folder.
  ///
  /// No confirmation: the tag naming dialog *is* the confirmation, it is one
  /// tap from being undone by retagging back, and the file stays in the same
  /// tier throughout — nothing leaves Photos and nothing is deleted.
  retag,
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
      showTelaToast(messenger, l10n.batchFavoriteDone(wallpapers.length));
      return true;
    case WallpaperBatchAction.unfavorite:
      await _unfavoriteAll(ref, wallpapers);
      showTelaToast(messenger, l10n.batchUnfavoriteDone(wallpapers.length));
      return true;
    case WallpaperBatchAction.download:
      return queueBatchDownload(
        context: context,
        ref: ref,
        wallpapers: wallpapers,
        messenger: messenger,
        l10n: l10n,
      );
    case WallpaperBatchAction.forget:
      await _forgetAll(ref, wallpapers);
      showTelaToast(messenger, l10n.batchForgetDone(wallpapers.length));
      return true;
    case WallpaperBatchAction.delete:
      return _deleteAll(context, ref, wallpapers, messenger, l10n);
    case WallpaperBatchAction.moveToPrivate:
      return _moveAllToPrivate(context, ref, wallpapers);
    case WallpaperBatchAction.retag:
      return _retagAll(context, ref, wallpapers);
    case WallpaperBatchAction.beam:
      return _beamAll(context, ref, wallpapers, messenger, l10n);
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

/// Sends every ticked download to a machine on the local network.
///
/// Reads the records for the same reason [_moveAllToPrivate] does: a beam needs
/// each file's location, not just its id — and it resolves them through
/// [ResolveBeamFiles] first, because a vault download's location is a
/// `content:` SAF URI no Dart code can open.
///
/// Answers false so the ticks survive: a beam takes nothing away and changes
/// nothing on this device, so there is no reason for the selection to clear.
Future<bool> _beamAll(
  BuildContext context,
  WidgetRef ref,
  List<Wallpaper> wallpapers,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
) async {
  final List<DownloadRecord> records = await _recordsFor(ref, wallpapers);
  if (!context.mounted) return false;
  final ResolvedBeamFiles resolved = await ref
      .read(resolveBeamFilesProvider)
      .call(<BeamCandidate>[
        for (final DownloadRecord record in records)
          BeamCandidate.ofDownload(record),
      ]);
  try {
    if (!context.mounted) return false;
    // A beam sends bytes, so a favourite nobody downloaded — or a download
    // whose file has since gone — has nothing to send. Said out loud, because
    // a button that silently does nothing reads as broken.
    if (resolved.files.isEmpty) {
      showTelaToast(messenger, l10n.beamNothingToSend(wallpapers.length));
      return false;
    }
    await BeamSheet.open(context, files: resolved.files);
  } finally {
    // The copies are full-size duplicates of every file sent; a batch of forty
    // left behind is forty wallpapers of cache.
    await resolved.release();
  }
  return false;
}

/// Refiles every ticked download under a tag the user names.
///
/// Reads the records for the same reason [_moveAllToPrivate] does: a retag
/// needs each file's tier and location, not just its id.
Future<bool> _retagAll(
  BuildContext context,
  WidgetRef ref,
  List<Wallpaper> wallpapers,
) async {
  final List<DownloadRecord> records = await _recordsFor(ref, wallpapers);
  if (!context.mounted) return false;
  return retagDownloads(context: context, ref: ref, records: records);
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
    showTelaToast(messenger, l10n.batchDeleteDone(total));
    return;
  }
  showTelaToast(
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

Future<void> _forgetAll(WidgetRef ref, List<Wallpaper> wallpapers) async {
  await ref.read(downloadHistoryProvider).forgetAll(<WallpaperRef>[
    for (final Wallpaper wallpaper in wallpapers) wallpaper.ref,
  ]);
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
