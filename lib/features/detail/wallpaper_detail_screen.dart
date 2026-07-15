import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/storage_tier_text.dart';
import 'package:tela/core/ui/wallpaper_failure_text.dart';
import 'package:tela/core/ui/wallpaper_share_sheet.dart';
import 'package:tela/core/ui/wallpaper_target_sheet.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/share_option.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_link.dart';
import 'package:tela/domain/models/wallpaper_share_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/ports/wallhaven_api.dart';
import 'package:tela/domain/use_cases/share_wallpaper.dart';
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
  bool _isSharing = false;

  Future<void> _chooseTarget() async {
    final WallpaperTarget? target = await chooseWallpaperTarget(context);
    if (target == null || !mounted) return;
    await _apply(target);
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
  ///
  /// Invalidates both listings the download may have just changed. They are
  /// plain (non-autoDispose) futures, so each resolves once per process and
  /// then caches — without this a download lands on disk and in the database
  /// while the screens that exist to show it keep rendering the world as it
  /// looked when they were first opened. It presented as "the download did not
  /// save", and only a relaunch made it appear (found on hardware, 2026-07-14).
  /// Which of the two is stale depends on the wallpaper's purity, so both are
  /// dropped rather than the caller guessing.
  Future<void> _download([StorageTier? tier]) async {
    setState(() => _isDownloading = true);
    try {
      await ref.read(downloadWallpaperProvider)(widget.wallpaper, tier: tier);
      ref
        ..invalidate(recentDownloadsProvider)
        ..invalidate(privateImagesProvider);
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

  /// Offers only the share options this wallpaper's purity allows, so an
  /// explicit wallpaper is never given the chance to send its image file — the
  /// menu and the use case enforce the same rule (see [shareOptionsFor]).
  Future<void> _chooseShare() async {
    final ShareOption? option = await chooseShareOption(
      context,
      shareOptionsFor(widget.wallpaper.purity),
    );
    if (option == null || !mounted) return;
    await _share(option);
  }

  Future<void> _share(ShareOption option) async {
    setState(() => _isSharing = true);
    try {
      final ShareWallpaper share = ref.read(shareWallpaperProvider);
      await switch (option) {
        ShareOption.link => share.link(widget.wallpaper),
        ShareOption.image => share.image(widget.wallpaper),
      };
    } on WallpaperShareFailure {
      if (mounted) _showResult(AppLocalizations.of(context).detailShareFailure);
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  /// Pushes the listing behind a tag or an uploader, rather than replacing this
  /// one, so Back returns to the wallpaper the link was printed on and the
  /// browse tabs are left exactly as the user had them.
  void _follow(WallpaperLink link) {
    unawaited(
      context.pushNamed(TelaRoutes.linkedListingName, extra: link),
    );
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
          _shareButton(l10n),
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
      data: (WallpaperDetails value) =>
          WallpaperMetadata(details: value, onFollow: _follow),
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

  Widget _shareButton(AppLocalizations l10n) {
    return IconButton(
      onPressed: _isSharing ? null : _chooseShare,
      tooltip: l10n.detailShare,
      icon: _isSharing
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.share_outlined),
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
