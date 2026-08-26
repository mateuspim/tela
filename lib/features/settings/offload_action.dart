import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/offload_run_controller.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/byte_size_text.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/download_location.dart';
import 'package:tela/domain/models/offload_group.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';
import 'package:tela/domain/models/stored_image_move.dart';
import 'package:tela/features/settings/download_location_controller.dart';

/// Grants a card folder, confirms, moves [groups], and re-routes new downloads.
///
/// The whole button, in the order the steps have to happen:
///
/// 1. **The folder first.** This tier cannot write without a user-granted tree,
///    and discovering that after copying nothing is a wall with no explanation
///    — the same reason `confirmAndMoveOutOfPrivate` grants before it copies.
/// 2. The card's own room, checked before the user is asked to commit — see
///    [_fits] for why a full card is refused rather than discovered.
/// 3. The confirmation, which names the count and the space.
/// 4. The move, handed to the background runner and **not awaited** — see
///    [_start] and `OffloadRunController`.
///
/// The re-route that follows a successful move is the runner's, for the same
/// reason the tally is: this function is gone long before either exists.
///
/// Returns whether a run started, which is not the same as whether anything
/// moved — nothing here knows that yet.
Future<bool> runOffload({
  required BuildContext context,
  required WidgetRef ref,
  required List<OffloadGroup> groups,
}) async {
  final List<StoredImageMove> moves = <StoredImageMove>[
    for (final OffloadGroup group in groups) ...group.moves,
  ];
  if (moves.isEmpty) return false;
  final DownloadFolder? card = await _grantCardFolder(ref);
  if (card == null || !context.mounted) return false;
  final int bytes = groups.fold(0, (int sum, OffloadGroup g) => sum + g.bytes);
  if (!_fits(context, card, bytes)) return false;
  if (!await _confirm(context, count: moves.length, bytes: bytes)) return false;
  return _start(ref, groups);
}

/// Points the files tier at the card, opening the picker when it is not there
/// already, and answers the folder it will write into.
///
/// Re-uses the settings controller rather than calling the store directly, so
/// the location row behind this screen shows the new folder the moment the
/// picker closes. Answers null for a backed-out picker, an ejected card, or a
/// folder that came back on built-in storage — all three leave nothing to move
/// *to*, and none of them is an error worth a red toast.
Future<DownloadFolder?> _grantCardFolder(WidgetRef ref) async {
  final DownloadLocation before = await ref.read(
    downloadLocationProvider.future,
  );
  final DownloadFolder? ready = _readyCard(before);
  if (ready != null) return ready;
  await ref
      .read(downloadLocationProvider.notifier)
      .choose(StorageVolumeKind.sdCard);
  return _readyCard(await ref.read(downloadLocationProvider.future));
}

DownloadFolder? _readyCard(DownloadLocation location) {
  final DownloadFolder? folder = location.folder;
  if (folder == null || !folder.isRemovable || !folder.isAvailable) return null;
  return folder;
}

/// Whether [card] can hold [bytes], refusing loudly when it cannot.
///
/// Checked before the confirmation rather than left to the move, because a copy
/// that runs the card out of space does not fail cleanly: it reports "moved 40
/// of 300" and leaves the library split across two disks with no record of
/// which half went where. A card whose free space cannot be read is let
/// through — an unanswerable question is not a no, and the partial report is
/// still the backstop.
bool _fits(BuildContext context, DownloadFolder card, int bytes) {
  final int? free = card.freeBytes;
  if (free == null || free >= bytes) return true;
  showTelaToast(
    ScaffoldMessenger.of(context),
    AppLocalizations.of(
      context,
    ).offloadCardFull(formatBytes(free), formatBytes(bytes)),
    kind: ToastKind.failure,
  );
  return false;
}

Future<bool> _confirm(
  BuildContext context, {
  required int count,
  required int bytes,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(l10n.offloadConfirmTitle(count)),
      content: Text(l10n.offloadConfirmBody(formatBytes(bytes))),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.offloadAction),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Hands the move to the background runner and answers whether it started.
///
/// **Returns as soon as the run is under way, not when it finishes.** That is
/// the point: a whole library moving to a card is minutes of copying, and the
/// modal this replaced pinned the user to the screen for all of them. Progress
/// and the final tally come from [offloadRunProvider], which lives above every
/// screen — so leaving Settings, browsing, or locking the phone does not stop
/// it.
bool _start(WidgetRef ref, List<OffloadGroup> groups) =>
    ref.read(offloadRunProvider.notifier).start(groups);
