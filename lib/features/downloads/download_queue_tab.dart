import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/download_queue_controller.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/network/wallpaper_image_caches.dart';
import 'package:tela/core/ui/wallpaper_status_view.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/queued_download.dart';

/// The downloads still owed, with a way to stop, retry or drop each one.
///
/// A list and not a grid, deliberately: a queue entry's subject is its *state*
/// — waiting, downloading, failed and why — and a wall of thumbnails is the one
/// layout with nowhere to put that. It also keeps a hundred rows cheap, which a
/// justified grid of a hundred originals is not.
class DownloadQueueTab extends ConsumerWidget {
  /// Creates the queue tab.
  const DownloadQueueTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<QueuedDownload>> queue = ref.watch(
      downloadQueueControllerProvider,
    );
    return queue.when(
      data: (List<QueuedDownload> entries) =>
          _body(context, ref, l10n, entries),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stack) => WallpaperStatusView(
        icon: Icons.error_outline,
        message: l10n.errorUnexpected,
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    List<QueuedDownload> entries,
  ) {
    if (entries.isEmpty) {
      return WallpaperStatusView(
        icon: Icons.download_done_outlined,
        message: l10n.downloadQueueEmpty,
      );
    }
    return Column(
      children: <Widget>[
        _DownloadQueueBar(entries: entries),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (BuildContext context, int index) =>
                _DownloadQueueRow(entry: entries[index]),
          ),
        ),
      ],
    );
  }
}

/// The count, and the controls that act on the whole queue.
class _DownloadQueueBar extends ConsumerWidget {
  const _DownloadQueueBar({required this.entries});

  final List<QueuedDownload> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool paused = ref.watch(downloadQueuePausedProvider);
    final int failed = failedDownloads(entries);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              _summary(l10n, paused: paused, failed: failed),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (failed > 0)
            TextButton(
              onPressed: () => ref
                  .read(downloadQueueControllerProvider.notifier)
                  .retryFailed(),
              child: Text(l10n.downloadQueueRetryAll),
            ),
          IconButton(
            onPressed: () => _togglePause(ref, paused: paused),
            icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            tooltip: paused
                ? l10n.downloadQueueResume
                : l10n.downloadQueuePause,
          ),
          IconButton(
            onPressed: () =>
                ref.read(downloadQueueControllerProvider.notifier).cancelAll(),
            icon: const Icon(Icons.clear_all),
            tooltip: l10n.downloadQueueCancelAll,
          ),
        ],
      ),
    );
  }

  /// The one line that has to stay true: how many are still owed, and — when
  /// some have failed — that they are waiting on the user rather than on the
  /// network. A bare "3 left" over four failures is the aggregate lie the batch
  /// snackbar used to tell.
  String _summary(
    AppLocalizations l10n, {
    required bool paused,
    required int failed,
  }) {
    final int owed = owedDownloads(entries);
    if (failed > 0) return l10n.downloadQueueSummaryFailed(owed, failed);
    return paused
        ? l10n.downloadQueueSummaryPaused(owed)
        : l10n.downloadQueueSummary(owed);
  }

  void _togglePause(WidgetRef ref, {required bool paused}) {
    final DownloadQueueController queue = ref.read(
      downloadQueueControllerProvider.notifier,
    );
    if (paused) {
      queue.resume();
      return;
    }
    queue.pause();
  }
}

/// One entry: what it is, where it got to, and the one action it offers.
class _DownloadQueueRow extends ConsumerWidget {
  const _DownloadQueueRow({required this.entry});

  final QueuedDownload entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // An explicit entry is not identified on this list until the private
    // library has been unlocked this session. The queue is allowed to *hold*
    // one — refusing would silently decline a download the user asked for — but
    // this tab sits behind no app-lock and no FLAG_SECURE, and a thumbnail and
    // an id on it would be exactly the ungated index the private tier exists to
    // prevent. The row still counts, still drains, and still offers its
    // controls; only the identifying half is withheld.
    final bool identify =
        !entry.wallpaper.isNsfw || ref.watch(queueRevealsPrivateProvider);
    return ListTile(
      leading: _leading(context, identify: identify),
      title: Text(
        identify ? entry.wallpaper.id : l10n.downloadQueuePrivateEntry,
      ),
      subtitle: Text(_status(l10n)),
      trailing: _trailing(context, ref, l10n),
    );
  }

  Widget _leading(BuildContext context, {required bool identify}) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    if (!identify) {
      return CircleAvatar(
        backgroundColor: colors.surfaceContainerHighest,
        child: Icon(Icons.lock_outline, color: colors.onSurfaceVariant),
      );
    }
    return SizedBox(
      width: 56,
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: entry.wallpaper.thumbSmallUrl,
          cacheManager: thumbnailImageCache,
          fit: BoxFit.cover,
          errorWidget: (BuildContext context, String url, Object error) =>
              ColoredBox(color: colors.surfaceContainerHighest),
        ),
      ),
    );
  }

  /// Where this entry got to, in a sentence. A failure names its reason: "it
  /// failed" with no why is a row the user cannot act on.
  String _status(AppLocalizations l10n) {
    return switch (entry.state) {
      DownloadQueueState.pending => l10n.downloadQueueWaiting,
      DownloadQueueState.running => l10n.downloadQueueDownloading,
      DownloadQueueState.failed => l10n.downloadQueueFailed(
        _reason(l10n, entry.failure ?? ImageStoreProblem.unknown),
        entry.attempts,
      ),
    };
  }

  String _reason(AppLocalizations l10n, ImageStoreProblem problem) {
    return switch (problem) {
      ImageStoreProblem.source => l10n.downloadQueueReasonSource,
      ImageStoreProblem.unavailable => l10n.downloadQueueReasonUnavailable,
      ImageStoreProblem.notConfigured => l10n.downloadQueueReasonNotConfigured,
      ImageStoreProblem.folderUnavailable =>
        l10n.downloadQueueReasonFolderUnavailable,
      ImageStoreProblem.restricted => l10n.downloadQueueReasonRestricted,
      ImageStoreProblem.unknown => l10n.downloadQueueReasonUnknown,
    };
  }

  Widget _trailing(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final DownloadQueueController queue = ref.read(
      downloadQueueControllerProvider.notifier,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (entry.state == DownloadQueueState.running)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (entry.state == DownloadQueueState.failed)
          IconButton(
            onPressed: () => queue.retry(entry.ref),
            icon: const Icon(Icons.refresh),
            tooltip: l10n.downloadQueueRetry,
          ),
        IconButton(
          onPressed: () => queue.cancel(entry.ref),
          icon: const Icon(Icons.close),
          tooltip: l10n.downloadQueueCancel,
        ),
      ],
    );
  }
}
