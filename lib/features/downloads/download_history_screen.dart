import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';
import 'package:tela/core/ui/wallpaper_target_sheet.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/downloads/download_history_providers.dart';

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
      appBar: AppBar(title: Text(l10n.downloadHistoryTitle)),
      body: downloads.when(
        data: (List<DownloadRecord> recent) => _grid(context, l10n, recent),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) =>
            Center(child: Text(l10n.errorUnexpected)),
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    AppLocalizations l10n,
    List<DownloadRecord> recent,
  ) {
    if (recent.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(l10n.downloadHistoryEmpty, textAlign: TextAlign.center),
        ),
      );
    }
    return MasonryGridView.count(
      crossAxisCount: wallpaperGridColumns(context),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      padding: const EdgeInsets.all(8),
      itemCount: recent.length,
      itemBuilder: (BuildContext context, int index) =>
          _tile(l10n, recent[index]),
    );
  }

  Widget _tile(AppLocalizations l10n, DownloadRecord download) {
    return Semantics(
      button: true,
      label: l10n.downloadHistorySetAgain(download.wallpaper.id),
      child: WallpaperTile(
        wallpaper: download.wallpaper,
        onTap: _isApplying ? null : () => _setAgain(download),
      ),
    );
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
