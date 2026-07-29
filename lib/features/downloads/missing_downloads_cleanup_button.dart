import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/wallpaper_batch_actions.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_selection.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/wallpaper.dart';

/// One tap on every history row [missingDownloadsProvider] has flagged, with
/// no ticking each one first.
///
/// The multi-select bar can already delete or redownload a tick, but ticking
/// stale rows one at a time is exactly the workflow a whole-history cleanup
/// exists to skip — this button already knows which rows they are, from the
/// same provider the missing badge reads. Hidden while nothing is missing, and
/// while already selecting: the contextual bar owns the screen then.
class MissingDownloadsCleanupButton extends ConsumerWidget {
  /// Creates the cleanup action for the history app bar.
  const MissingDownloadsCleanupButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (WallpaperSelectionScope.isActive(context)) {
      return const SizedBox.shrink();
    }
    final List<Wallpaper> missing = _missingWallpapers(ref);
    if (missing.isEmpty) return const SizedBox.shrink();
    final AppLocalizations l10n = AppLocalizations.of(context);
    return IconButton(
      icon: const Icon(Icons.cleaning_services_outlined),
      tooltip: l10n.downloadHistoryCleanupTooltip,
      onPressed: () => _choose(context, ref, l10n, missing),
    );
  }

  /// The history rows flagged missing, resolved back to wallpapers so
  /// `runWallpaperBatchAction` can act on them directly.
  List<Wallpaper> _missingWallpapers(WidgetRef ref) {
    final List<DownloadRecord> recent =
        ref.watch(recentDownloadsProvider).value ?? const <DownloadRecord>[];
    final Set<String> missing =
        ref.watch(missingDownloadsProvider).value ?? const <String>{};
    return <Wallpaper>[
      for (final DownloadRecord record in recent)
        if (missing.contains(record.wallpaper.ref.key)) record.wallpaper,
    ];
  }

  /// Asks which of the two fates the missing rows get, then runs it.
  ///
  /// Deliberately asks nothing else: `delete` still shows its own destructive
  /// confirmation, so this dialog would only be repeating that warning.
  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    List<Wallpaper> missing,
  ) async {
    final WallpaperBatchAction? action = await showDialog<WallpaperBatchAction>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.downloadHistoryCleanupTitle(missing.length)),
        content: Text(l10n.downloadHistoryCleanupBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, WallpaperBatchAction.download),
            child: Text(l10n.downloadHistoryCleanupRedownload),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, WallpaperBatchAction.delete),
            child: Text(l10n.downloadHistoryCleanupDelete),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;
    await runWallpaperBatchAction(
      context: context,
      ref: ref,
      action: action,
      wallpapers: missing,
    );
  }
}
