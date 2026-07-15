import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_route_transitions.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/immersive_system_ui.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
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
import 'package:tela/features/detail/wallpaper_immersive_session.dart';
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
  const WallpaperDetailScreen({
    this.wallpaper,
    this.gallerySession,
    this.immersiveSystemUi = const FlutterImmersiveSystemUi(),
    super.key,
  }) : assert(
         (wallpaper == null) != (gallerySession == null),
         'provide either wallpaper or gallerySession',
       );

  /// The selected wallpaper, including its full-resolution URL.
  final Wallpaper? wallpaper;

  /// An ordered shelf snapshot. Its creator retains disposal ownership.
  final GallerySessionController<Wallpaper>? gallerySession;

  /// The Android system-chrome seam used by the immersive preview.
  final ImmersiveSystemUi immersiveSystemUi;

  @override
  ConsumerState<WallpaperDetailScreen> createState() =>
      _WallpaperDetailScreenState();
}

class _WallpaperDetailScreenState extends ConsumerState<WallpaperDetailScreen> {
  late final GallerySessionController<Wallpaper> _gallery;
  late final bool _ownsGallery;
  bool _isApplying = false;
  bool _isDownloading = false;
  bool _isSharing = false;

  Wallpaper get _wallpaper => _gallery.selectedItem;

  @override
  void initState() {
    super.initState();
    _ownsGallery = widget.gallerySession == null;
    _gallery =
        widget.gallerySession ??
        GallerySessionController<Wallpaper>(
          identity: 'wallpaper:${widget.wallpaper!.id}',
          items: <Wallpaper>[widget.wallpaper!],
          initialIndex: 0,
        );
    _gallery.addListener(_selectionChanged);
  }

  void _selectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _gallery.removeListener(_selectionChanged);
    if (_ownsGallery) _gallery.dispose();
    super.dispose();
  }

  Future<void> _chooseTarget() async {
    final WallpaperTarget? target = await chooseWallpaperTarget(context);
    if (target == null || !mounted) return;
    await _apply(target);
  }

  Future<void> _apply(WallpaperTarget target) async {
    setState(() => _isApplying = true);
    try {
      await ref.read(applyWallpaperProvider)(_wallpaper, target);
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
            _wallpaper.purity,
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
      await ref.read(downloadWallpaperProvider)(_wallpaper, tier: tier);
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
      shareOptionsFor(_wallpaper.purity),
    );
    if (option == null || !mounted) return;
    await _share(option);
  }

  Future<void> _share(ShareOption option) async {
    setState(() => _isSharing = true);
    try {
      final ShareWallpaper share = ref.read(shareWallpaperProvider);
      await switch (option) {
        ShareOption.link => share.link(_wallpaper),
        ShareOption.image => share.image(_wallpaper),
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
      wallpaperDetailsProvider(_wallpaper.id),
    );
    final bool expanded = MediaQuery.sizeOf(context).width >= _expandedWidth;
    return Scaffold(
      appBar: AppBar(
        title: Text(_wallpaper.resolution.toString()),
        actions: expanded ? null : _compactActions(l10n),
      ),
      body: expanded
          ? _expandedBody(details, l10n)
          : _compactBody(details, l10n),
    );
  }

  static const double _expandedWidth = 840;

  List<Widget> _compactActions(AppLocalizations l10n) {
    return <Widget>[
      FavoriteButton(wallpaper: _wallpaper),
      _shareButton(l10n),
      _downloadButton(l10n),
    ];
  }

  Widget _compactBody(
    AsyncValue<WallpaperDetails> details,
    AppLocalizations l10n,
  ) {
    final double previewHeight = (MediaQuery.sizeOf(context).height * .58)
        .clamp(320, 560);
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            children: <Widget>[
              SizedBox(height: previewHeight, child: _preview()),
              _metadata(details, l10n),
            ],
          ),
        ),
        _applyButton(l10n),
      ],
    );
  }

  Widget _expandedBody(
    AsyncValue<WallpaperDetails> details,
    AppLocalizations l10n,
  ) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: ColoredBox(
                key: const Key('detail-preview-pane'),
                color: Colors.black,
                child: _preview(),
              ),
            ),
          ),
        ),
        SizedBox(
          key: const Key('detail-information-pane'),
          width: 440,
          child: ColoredBox(
            color: colors.surfaceContainerLow,
            child: Column(
              children: <Widget>[
                _expandedActions(l10n),
                const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    child: _metadata(details, l10n),
                  ),
                ),
                _applyButton(l10n),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _preview() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ProgressiveWallpaperPreview(
          wallpaper: _wallpaper,
          heroTag: shelfHeroTag(
            _gallery.identity,
            _wallpaper.id,
            _gallery.selectedIndex,
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: IconButton.filledTonal(
            onPressed: _enterFullscreen,
            tooltip: AppLocalizations.of(context).detailEnterFullscreen,
            icon: const Icon(Icons.fullscreen),
          ),
        ),
      ],
    );
  }

  void _enterFullscreen() {
    unawaited(Navigator.of(context).push<void>(_fullscreenRoute(context)));
  }

  PageRoute<void> _fullscreenRoute(BuildContext context) {
    final Duration duration = galleryTransitionDuration(context);
    return PageRouteBuilder<void>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) => _fullscreenSurface(context),
      transitionsBuilder: _fadeFullscreenRoute,
    );
  }

  Widget _fullscreenSurface(BuildContext routeContext) {
    return WallpaperImmersiveSession(
      gallery: _gallery,
      systemUi: widget.immersiveSystemUi,
      onClose: () async => Navigator.of(routeContext).pop(),
    );
  }

  Widget _fadeFullscreenRoute(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }

  Widget _expandedActions(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: <Widget>[
          FavoriteButton(wallpaper: _wallpaper),
          const Spacer(),
          _shareButton(l10n),
          _downloadButton(l10n),
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
