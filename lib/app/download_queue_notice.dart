import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart'
    show BuildContext, basicLocaleListResolution;
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
/// **Started from `main`, on the container, and deliberately not from a
/// widget.** It used to be one, for the strings — [AppLocalizations] is
/// normally reached through a [BuildContext] — and that stopped being possible
/// the moment the Flutter engine outlived the activity. A destroyed activity
/// takes the rendering surface with it, so no frames are produced and no widget
/// rebuilds: a notice that announced from `build` would freeze at whatever
/// count was on screen when the user swiped tela away, and never release. The
/// queue itself is unaffected — the drain is futures, not frames — and so is
/// this, because a Riverpod listener falls back to a timer when no frame
/// arrives to carry it.
///
/// The words come from [shadeWords] instead, which needs no context and still
/// reads the ARB, so adding a locale stays a translation file (CLAUDE.md).
///
/// ```dart
/// anchorOwedDownloads(container); // in main, once
/// ```
void anchorOwedDownloads(ProviderContainer container) {
  final DownloadQueueAnchor anchor = container.read(
    downloadQueueAnchorProvider,
  );
  container.listen<int?>(
    owedDownloadNoticeProvider,
    (int? previous, int? owed) => _announce(anchor, owed),
    // The queue a killed session left behind is already owed before anything
    // else runs, and there is no change to wait for: it is the state we start
    // in. Announcing it immediately is what re-raises the anchor for a batch
    // the user never got to see finish.
    fireImmediately: true,
  );
}

/// The shipped strings for the platform's locale, with no [BuildContext].
///
/// Resolved the way `WidgetsApp` resolves its own — the platform's preferred
/// locales against the ones tela ships — so a second locale is picked up here
/// by existing, not by editing this function. English is the only one shipped
/// today, and that stays a fact about the ARB rather than one written in Dart.
AppLocalizations shadeWords() {
  return lookupAppLocalizations(
    basicLocaleListResolution(
      PlatformDispatcher.instance.locales,
      AppLocalizations.supportedLocales,
    ),
  );
}

/// Tells [anchor] about [owed]. Fire-and-forget on purpose: the shade catching
/// up a frame late costs nothing, and awaiting a platform channel here would
/// put the queue's own progress behind a notification.
void _announce(DownloadQueueAnchor anchor, int? owed) {
  if (owed == null) {
    unawaited(anchor.release());
    return;
  }
  final AppLocalizations l10n = shadeWords();
  unawaited(
    anchor.hold(
      title: l10n.downloadQueueNoticeTitle,
      body: l10n.downloadQueueNoticeBody(owed),
    ),
  );
}
