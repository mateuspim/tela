import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/download_volume_sheet.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image_move.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

/// Confirms, moves the downloads into the private library, and reports.
///
/// The one entry point every "Move to private library" uses — the batch bar,
/// both viewers and the detail screen — so the confirmation wording and the
/// honest tally are written once.
///
/// Returns whether anything moved, so a viewer can close and a screen can
/// refresh only when something changed. A declined confirmation, a declined
/// system delete prompt and a failure all answer false.
///
/// ```dart
/// final bool moved = await confirmAndMoveToPrivate(
///   context: context, ref: ref, records: <DownloadRecord>[record]);
/// if (moved) Navigator.of(context).maybePop();
/// ```
Future<bool> confirmAndMoveToPrivate({
  required BuildContext context,
  required WidgetRef ref,
  required List<DownloadRecord> records,
}) async {
  if (records.isEmpty) return false;
  final AppLocalizations l10n = AppLocalizations.of(context);
  final bool confirmed = await _confirm(
    context,
    title: l10n.moveToPrivateTitle(records.length),
    body: l10n.moveToPrivateBody(records.length),
    action: l10n.moveToPrivateAction,
  );
  if (!confirmed || !context.mounted) return false;
  return moveToPrivate(context: context, ref: ref, records: records);
}

/// The same move **without** the confirmation.
///
/// For the one caller that has already asked: the multi-select bar routes
/// every destructive batch through `runWallpaperBatchAction`, which confirms
/// before it dispatches. Going through [confirmAndMoveToPrivate] there would
/// ask twice, which is how a user learns to dismiss the dialog that matters.
Future<bool> moveToPrivate({
  required BuildContext context,
  required WidgetRef ref,
  required List<DownloadRecord> records,
}) async {
  if (records.isEmpty) return false;
  final AppLocalizations l10n = AppLocalizations.of(context);
  // Read before the move's async gap: a viewer pops itself on success, so the
  // messenger it reports through must be captured while its context is alive.
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  return _moveAndReport(
    ref,
    messenger,
    l10n,
    moves: <StoredImageMove>[
      for (final DownloadRecord record in records)
        StoredImageMove(
          ref: record.wallpaper.ref,
          purity: record.wallpaper.purity,
          from: record.tier,
          location: record.location,
          to: StorageTier.appPrivate,
        ),
    ],
    done: l10n.moveToPrivateDone,
    partial: l10n.moveToPrivatePartial,
  );
}

/// Confirms, moves the images out to the files folder, and reports.
///
/// The counterpart, and it is **not** symmetric — see [StoredImageMove]. It can
/// only ever target [StorageTier.filesOutsideGallery], because the private tier
/// keeps no record of what it holds beyond a file name, so tela cannot prove an
/// image is safe for Photos. Every move therefore declares `nsfw` and lets the
/// storage adapter refuse the gallery on its own.
///
/// Grants the destination folder **before** anything is copied: that tier needs
/// a user-granted folder, and finding that out after copying nothing is a wall
/// with no explanation. A backed-out chooser moves nothing and answers false.
///
/// Images already in the vault are **dropped from the selection**, because for
/// them this move has no destination to go to: they are on the files tier
/// already, and asking to move them there again would have the copy overwrite
/// the document it is reading and the delete then remove it. An all-vault
/// selection answers false without asking anything.
Future<bool> confirmAndMoveOutOfPrivate({
  required BuildContext context,
  required WidgetRef ref,
  required List<PrivateImage> images,
}) async {
  // **Vault images are already out**, and letting one through here would not
  // merely be a no-op: it is `filesOutsideGallery` to `filesOutsideGallery` at
  // `nsfw`, so the copy resolves to the very document it is reading, overwrites
  // it in place, and the delete that follows then removes the file it just
  // wrote. Filtered rather than refused whole, so a mixed selection still moves
  // the app-private half it really can. See `PrivateImage.tier`.
  final List<PrivateImage> movable = <PrivateImage>[
    for (final PrivateImage image in images)
      if (image.tier == StorageTier.appPrivate) image,
  ];
  if (movable.isEmpty) return false;
  final AppLocalizations l10n = AppLocalizations.of(context);
  final bool confirmed = await _confirm(
    context,
    title: l10n.moveOutOfPrivateTitle(movable.length),
    body: l10n.moveOutOfPrivateBody(movable.length),
    action: l10n.moveOutOfPrivateAction,
  );
  if (!confirmed || !context.mounted) return false;
  final bool ready = await ref
      .read(configuredDownloadProvider)
      .ensureFolder(
        ({required bool offerSdCard}) =>
            chooseDownloadVolume(context, offerSdCard: offerSdCard),
        // Every move out declares nsfw (see below), so the explicit folder is
        // the one these land in.
        purities: <Purity>{Purity.nsfw},
      );
  if (!ready || !context.mounted) return false;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  return _moveAndReport(
    ref,
    messenger,
    l10n,
    moves: <StoredImageMove>[
      for (final PrivateImage image in movable)
        StoredImageMove(
          ref: image.ref,
          // Not a claim that it is explicit — a refusal to claim it is not.
          // The adapter's own gate then makes the gallery impossible.
          purity: Purity.nsfw,
          from: StorageTier.appPrivate,
          location: image.location,
          to: StorageTier.filesOutsideGallery,
        ),
    ],
    done: l10n.moveOutOfPrivateDone,
    partial: l10n.moveOutOfPrivatePartial,
  );
}

/// Runs the moves and says what really happened.
///
/// [done] is only used when every move landed. Anything less takes [partial],
/// with no success tick: some of those images are still where they were, and
/// that is the outcome the user has to act on.
Future<bool> _moveAndReport(
  WidgetRef ref,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n, {
  required List<StoredImageMove> moves,
  required String Function(int count) done,
  required String Function(int moved, int total) partial,
}) async {
  try {
    final Set<WallpaperRef> moved = await ref.read(moveStoredImagesProvider)(
      moves,
    );
    refreshDownloads(ref);
    if (moved.length == moves.length) {
      showTelaToast(messenger, done(moves.length));
      return true;
    }
    showTelaToast(
      messenger,
      partial(moved.length, moves.length),
      kind: ToastKind.failure,
    );
    return moved.isNotEmpty;
  } on ImageStoreFailure {
    showTelaToast(messenger, l10n.moveFailure, kind: ToastKind.failure);
    return false;
  }
}

/// The confirmation both directions share. Each supplies its own words: the two
/// moves promise genuinely different things, and one generic sentence over both
/// would have to be vague about the half that matters.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
