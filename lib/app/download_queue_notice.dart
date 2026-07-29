import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/download_queue_controller.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/queued_download.dart';
import 'package:tela/domain/ports/download_queue_anchor.dart';

/// How many downloads the shade should say are still owed, or null for silence.
///
/// A plain derived provider so the whole rule is readable — and testable —
/// without a widget: **anchor exactly while work is genuinely in flight.**
///
/// A paused queue answers null even holding ninety entries. Nothing is
/// downloading, so there is nothing to protect from a low-memory kill, and an
/// ongoing notification for work that has stopped is a lie in the one place
/// the user cannot dismiss. Failed entries do not count either —
/// [owedDownloads] already excludes them — because a queue of nothing but
/// failures is waiting on the user, not on the network.
final Provider<int?> owedDownloadNoticeProvider = Provider<int?>((Ref ref) {
  if (ref.watch(downloadQueuePausedProvider)) return null;
  final List<QueuedDownload> entries =
      ref.watch(downloadQueueControllerProvider).value ??
      const <QueuedDownload>[];
  final int owed = owedDownloads(entries);
  return owed == 0 ? null : owed;
});

/// Raises the queue's process anchor while downloads are owed, and drops it
/// after.
///
/// **A widget, and it has to be one, for the strings.** The notification's
/// title and body are user-facing text, so they come from the ARB like
/// everything else (CLAUDE.md); [AppLocalizations] is reached through a
/// [BuildContext], and the controller has none. Sitting inside
/// `MaterialApp.builder` puts it under the
/// localizations delegate while still above every route, so the anchor does not
/// come and go with whichever screen is open — a queue draining behind the
/// browse wall is the ordinary case.
///
/// It renders [child] untouched and lays out nothing of its own.
///
/// Backgrounding does not stop it: a Riverpod listener fires on the state
/// change, not on a frame, so a batch the user switched away from keeps
/// updating its own count. What does stop it is the activity being destroyed,
/// which today takes the Flutter engine and the drain with it — see the queue's
/// slice-2 notes in HANDOFF.md.
class DownloadQueueNotice extends ConsumerWidget {
  /// Wraps [child], watching the queue on its behalf.
  const DownloadQueueNotice({required this.child, super.key});

  /// The tree this reports for, returned from `build` unchanged.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched and announced on every build rather than listened for changes:
    // a change listener says nothing about the value it *starts* at, and the
    // queue a killed session left behind is already loaded before any route
    // mounts. Re-announcing costs nothing — the adapter drops a hold whose
    // words have not changed — and nothing here feeds back into a provider, so
    // there is no rebuild to loop on.
    _announce(
      ref.read(downloadQueueAnchorProvider),
      ref.watch(owedDownloadNoticeProvider),
      context,
    );
    return child;
  }

  /// Tells the anchor about [owed]. Fire-and-forget on purpose: the shade
  /// catching up a frame late costs nothing, and awaiting a platform channel
  /// here would put the queue's own progress behind a notification.
  void _announce(DownloadQueueAnchor anchor, int? owed, BuildContext context) {
    if (owed == null) {
      unawaited(anchor.release());
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    unawaited(
      anchor.hold(
        title: l10n.downloadQueueNoticeTitle,
        body: l10n.downloadQueueNoticeBody(owed),
      ),
    );
  }
}
