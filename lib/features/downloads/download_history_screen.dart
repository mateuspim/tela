import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';
import 'package:tela/core/ui/wallpaper_status_view.dart';
import 'package:tela/core/ui/wallpaper_target_sheet.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';

/// The wallpapers already on this device, each one tap away from being set.
///
/// Tapping a tile sets it again, from the file the download left behind rather
/// than from Wallhaven — that is the whole point of keeping the history, so the
/// tile leads to the target sheet instead of back to the detail screen.
class DownloadHistoryScreen extends ConsumerStatefulWidget {
  /// Creates the download-history screen.
  const DownloadHistoryScreen({super.key});

  @override
  ConsumerState<DownloadHistoryScreen> createState() =>
      _DownloadHistoryScreenState();
}

class _DownloadHistoryScreenState extends ConsumerState<DownloadHistoryScreen> {
  bool _isApplying = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<DownloadRecord>> downloads = ref.watch(
      recentDownloadsProvider,
    );
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Text(
          l10n.downloadHistoryTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      body: downloads.when(
        data: (List<DownloadRecord> recent) => _grid(context, l10n, recent),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => WallpaperStatusView(
          icon: Icons.error_outline,
          message: l10n.errorUnexpected,
        ),
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    AppLocalizations l10n,
    List<DownloadRecord> recent,
  ) {
    if (recent.isEmpty) {
      return WallpaperStatusView(
        icon: Icons.download_outlined,
        message: l10n.downloadHistoryEmpty,
      );
    }
    return MasonryGridView.count(
      crossAxisCount: wallpaperGridColumns(context),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      padding: const EdgeInsets.all(12),
      itemCount: recent.length,
      itemBuilder: (BuildContext context, int index) =>
          _tile(l10n, recent[index]),
    );
  }

  /// One download, badged when its file is no longer on the device.
  ///
  /// The badge is not a warning that something is broken — the tile still works
  /// — it is the difference between "set this from the file you already have"
  /// and "re-download six megabytes first". Those are different actions and the
  /// grid should not present them identically. The badge simply does not appear
  /// while the probe is in flight, or if it fails: an unbadged tile is the
  /// status quo, and a history that will not render because a file check hung
  /// would be a worse screen than one that under-warns.
  Widget _tile(AppLocalizations l10n, DownloadRecord download) {
    final Set<String> missing =
        ref.watch(missingDownloadsProvider).value ?? const <String>{};
    final bool isMissing = missing.contains(download.wallpaper.id);
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: isMissing
          ? l10n.downloadHistoryRedownload(download.wallpaper.id)
          : l10n.downloadHistorySetAgain(download.wallpaper.id),
      child: Stack(
        children: <Widget>[
          Opacity(
            opacity: isMissing ? 0.55 : 1,
            child: WallpaperTile(
              wallpaper: download.wallpaper,
              onTap: _isApplying ? null : () => _setAgain(download),
              onLongPress: _isApplying ? null : () => _confirmForget(download),
            ),
          ),
          if (isMissing)
            Positioned(top: 8, right: 8, child: _missingBadge(context, l10n)),
        ],
      ),
    );
  }

  /// Says "this one comes from Wallhaven now", in the one word a badge has.
  Widget _missingBadge(BuildContext context, AppLocalizations l10n) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: l10n.downloadHistoryFileGone,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.85),
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.cloud_download_outlined,
            size: 18,
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// Asks before forgetting a row — and the *wording* is the feature.
  ///
  /// "Remove from history" and "delete the file" are two different actions, and
  /// this tile looks exactly like a file. So the confirmation says what will
  /// and will not happen in plain words: the row goes, the wallpaper stays
  /// where it was downloaded. Without that sentence this is a button that reads
  /// as "delete my wallpaper" to half the people who press it.
  Future<void> _confirmForget(DownloadRecord download) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.downloadHistoryForgetTitle),
        content: Text(l10n.downloadHistoryForgetBody),
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
    if (confirmed ?? false) await _forget(download);
  }

  Future<void> _forget(DownloadRecord download) async {
    await ref.read(downloadHistoryProvider).forget(download.wallpaper.id);
    ref.invalidate(recentDownloadsProvider);
  }

  Future<void> _setAgain(DownloadRecord download) async {
    final WallpaperTarget? target = await chooseWallpaperTarget(context);
    if (target == null || !mounted) return;
    setState(() => _isApplying = true);
    try {
      await ref.read(applyDownloadProvider)(download, target);
      if (mounted) _show(AppLocalizations.of(context).detailApplySuccess);
    } on WallpaperApplyFailure {
      if (mounted) _show(AppLocalizations.of(context).detailApplyFailure);
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
