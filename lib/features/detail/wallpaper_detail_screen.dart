import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/storage_tier_text.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/ports/wallhaven_api.dart';
import 'package:tela/features/browse/wallpaper_failure_text.dart';
import 'package:tela/features/detail/progressive_wallpaper_preview.dart';
import 'package:tela/features/detail/wallpaper_metadata.dart';
import 'package:tela/features/favorites/favorite_button.dart';

/// Loads complete metadata independently of the grid's fast listing response.
final FutureProviderFamily<WallpaperDetails, String> wallpaperDetailsProvider =
    FutureProvider.autoDispose.family<WallpaperDetails, String>((
      Ref ref,
      String id,
    ) {
      final WallhavenApi api = ref.watch(wallhavenApiProvider);
      return api.wallpaperDetails(id);
    });

/// Full-screen preview, metadata, and the shortest path to wallpaper apply.
class WallpaperDetailScreen extends ConsumerStatefulWidget {
  /// Creates the detail screen for a grid [wallpaper].
  const WallpaperDetailScreen({required this.wallpaper, super.key});

  /// The selected wallpaper, including its full-resolution URL.
  final Wallpaper wallpaper;

  @override
  ConsumerState<WallpaperDetailScreen> createState() =>
      _WallpaperDetailScreenState();
}

class _WallpaperDetailScreenState extends ConsumerState<WallpaperDetailScreen> {
  bool _isApplying = false;
  bool _isDownloading = false;

  Future<void> _chooseTarget() async {
    final WallpaperTarget? target = await showModalBottomSheet<WallpaperTarget>(
      context: context,
      builder: _targetSheet,
    );
    if (target == null || !mounted) return;
    await _apply(target);
  }

  Widget _targetSheet(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(title: Text(l10n.detailTargetTitle)),
          _targetTile(
            l10n.detailTargetHome,
            Icons.home_outlined,
            WallpaperTarget.home,
          ),
          _targetTile(
            l10n.detailTargetLock,
            Icons.lock_outline,
            WallpaperTarget.lock,
          ),
          _targetTile(
            l10n.detailTargetBoth,
            Icons.smartphone_outlined,
            WallpaperTarget.both,
          ),
        ],
      ),
    );
  }

  Widget _targetTile(String label, IconData icon, WallpaperTarget target) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () => Navigator.pop(context, target),
    );
  }

  Future<void> _apply(WallpaperTarget target) async {
    setState(() => _isApplying = true);
    try {
      await ref.read(applyWallpaperProvider)(widget.wallpaper, target);
      if (mounted) _showResult(AppLocalizations.of(context).detailApplySuccess);
    } on WallpaperApplyFailure {
      if (mounted) _showResult(AppLocalizations.of(context).detailApplyFailure);
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  Future<void> _chooseDownloadTier() async {
    final StorageTier? tier = await showModalBottomSheet<StorageTier>(
      context: context,
      builder: _downloadTierSheet,
    );
    if (tier == null || !mounted) return;
    await _download(tier);
  }

  /// Offers only the tiers this wallpaper's purity is allowed to land in, so a
  /// one-off override cannot do what the settings screen forbids.
  Widget _downloadTierSheet(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(title: Text(l10n.detailDownloadChooseTier)),
          for (final StorageTier tier in StorageSettings.choicesFor(
            widget.wallpaper.purity,
          ))
            _downloadTierTile(l10n, tier),
        ],
      ),
    );
  }

  Widget _downloadTierTile(AppLocalizations l10n, StorageTier tier) {
    return ListTile(
      leading: Icon(storageTierIcon(tier)),
      title: Text(storageTierLabel(l10n, tier)),
      onTap: () => Navigator.pop(context, tier),
    );
  }

  /// Downloads to [tier], or to the configured destination when it is null.
  Future<void> _download([StorageTier? tier]) async {
    setState(() => _isDownloading = true);
    try {
      await ref.read(downloadWallpaperProvider)(widget.wallpaper, tier: tier);
      if (mounted) {
        _showResult(AppLocalizations.of(context).detailDownloadSuccess);
      }
    } on ImageStoreFailure {
      if (mounted) {
        _showResult(AppLocalizations.of(context).detailDownloadFailure);
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showResult(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<WallpaperDetails> details = ref.watch(
      wallpaperDetailsProvider(widget.wallpaper.id),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.wallpaper.resolution.toString()),
        actions: <Widget>[
          FavoriteButton(wallpaper: widget.wallpaper),
          _downloadButton(l10n),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              children: <Widget>[
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * .52,
                  child: ProgressiveWallpaperPreview(
                    wallpaper: widget.wallpaper,
                  ),
                ),
                _metadata(details, l10n),
              ],
            ),
          ),
          _applyButton(l10n),
        ],
      ),
    );
  }

  Widget _metadata(
    AsyncValue<WallpaperDetails> details,
    AppLocalizations l10n,
  ) {
    return details.when(
      data: (WallpaperDetails value) => WallpaperMetadata(details: value),
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace stackTrace) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          error is WallhavenFailure
              ? localizedFailure(l10n, error)
              : l10n.errorUnexpected,
        ),
      ),
    );
  }

  Widget _applyButton(AppLocalizations l10n) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _isApplying ? null : _chooseTarget,
          icon: _isApplying
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wallpaper_outlined),
          label: Text(l10n.detailSetWallpaper),
        ),
      ),
    );
  }

  Widget _downloadButton(AppLocalizations l10n) {
    return Semantics(
      button: true,
      label: l10n.detailDownload,
      child: InkWell(
        onTap: _isDownloading ? null : _download,
        onLongPress: _isDownloading ? null : _chooseDownloadTier,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _isDownloading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined),
        ),
      ),
    );
  }
}
