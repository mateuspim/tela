import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/configured_download.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/download_volume_sheet.dart';
import 'package:tela/core/ui/gallery_route_transitions.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/immersive_system_ui.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
import 'package:tela/core/ui/storage_tier_text.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/core/ui/wallpaper_failure_text.dart';
import 'package:tela/core/ui/wallpaper_share_sheet.dart';
import 'package:tela/core/ui/wallpaper_target_sheet.dart';
import 'package:tela/domain/models/bitmap_export_rule.dart';
import 'package:tela/domain/models/external_link_failure.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/share_option.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_adjust_failure.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_link.dart';
import 'package:tela/domain/models/wallpaper_share_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/ports/wallhaven_api.dart';
import 'package:tela/domain/use_cases/share_wallpaper.dart';
import 'package:tela/features/browse/linked_listing_args.dart';
import 'package:tela/features/detail/crop_wallpaper_screen.dart';
import 'package:tela/features/detail/progressive_wallpaper_preview.dart';
import 'package:tela/features/detail/wallpaper_immersive_session.dart';
import 'package:tela/features/detail/wallpaper_metadata.dart';
import 'package:tela/features/favorites/favorite_button.dart';
import 'package:tela/features/settings/blocked_tags_providers.dart';

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
    this.originFilters,
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

  /// The filters of the listing this detail was opened from, forwarded to any
  /// tag or uploader followed from here so the drill-down inherits the world
  /// the user was already in — sketchy stays sketchy — rather than resetting to
  /// Browse's own. Null when the shelf had no filters to inherit (Favorites,
  /// History, a deep link), which falls back to Browse, as it always did.
  final SearchQuery? originFilters;

  /// The Android system-chrome seam used by the immersive preview.
  final ImmersiveSystemUi immersiveSystemUi;

  @override
  ConsumerState<WallpaperDetailScreen> createState() =>
      _WallpaperDetailScreenState();
}

class _WallpaperDetailScreenState extends ConsumerState<WallpaperDetailScreen> {
  late final GallerySessionController<Wallpaper> _gallery;
  late final bool _ownsGallery;
  late final PageController _pages;
  bool _isApplying = false;
  bool _isDownloading = false;
  bool _isSharing = false;
  bool _isAdjusting = false;

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
    _pages = PageController(initialPage: _gallery.selectedIndex);
    _gallery.addListener(_selectionChanged);
  }

  /// Keeps the preview pager and the rest of the screen on the session's
  /// selection, whichever moved it.
  ///
  /// A swipe drives the session through [_onPageTurned]; anything else — the
  /// chevrons, or the fullscreen viewer paging the shared session while Detail
  /// sits behind it — moves the session first, and the pager is caught up here.
  /// The guard makes the two directions one loop, not two: a swipe leaves the
  /// pager already on the selection, so nothing is jumped back.
  void _selectionChanged() {
    if (!mounted) return;
    if (_pages.hasClients && _pages.page?.round() != _gallery.selectedIndex) {
      _pages.jumpToPage(_gallery.selectedIndex);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _gallery.removeListener(_selectionChanged);
    _pages.dispose();
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
      if (mounted) {
        _showResult(
          AppLocalizations.of(context).detailApplyFailure,
          kind: ToastKind.failure,
        );
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  /// Frames the wallpaper before setting it — the long way round beside
  /// [_apply], which stays the shortest path (Wave 1's "≤3 taps").
  ///
  /// Two editors behind one button. An explicit wallpaper's pixels may not
  /// reach the OEM's editor (a separate app, [mayExportBitmap]), so it goes
  /// straight to tela's own in-app cropper. A safe one prefers the OEM editor —
  /// the same screen the gallery opens — and falls back to tela's cropper only
  /// where the device has none.
  Future<void> _adjust() async {
    if (!mayExportBitmap(_wallpaper.purity)) {
      _openCropEditor();
      return;
    }
    setState(() => _isAdjusting = true);
    final WallpaperAdjustFailure? failure = await _tryOpenSystemEditor();
    if (mounted) setState(() => _isAdjusting = false);
    if (failure == null || !mounted) return;
    if (failure.problem == WallpaperAdjustProblem.unavailable) {
      _openCropEditor();
    } else {
      _showResult(
        AppLocalizations.of(context).detailAdjustFailure,
        kind: ToastKind.failure,
      );
    }
  }

  /// Opens the OEM editor; returns null on success, or the failure to route on.
  ///
  /// Deliberately silent on success: tela launches the editor and never hears
  /// what the user did there, so it has no outcome it could honestly report.
  Future<WallpaperAdjustFailure?> _tryOpenSystemEditor() async {
    try {
      await ref.read(adjustWallpaperProvider)(_wallpaper);
      return null;
    } on WallpaperAdjustFailure catch (failure) {
      return failure;
    }
  }

  /// Pushes tela's own cropper. It applies and pops itself, so nothing is
  /// awaited here — the detail screen simply returns to view when it closes.
  void _openCropEditor() {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              CropWallpaperScreen(wallpaper: _wallpaper),
        ),
      ),
    );
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
      subtitle: Text(storageTierDetail(l10n, tier)),
      onTap: () => Navigator.pop(context, tier),
    );
  }

  /// Downloads to [tier], or to the configured destination when it is null.
  ///
  /// [refreshDownloads] is what makes the new file visible to the screens that
  /// exist to show it; see its docstring for why skipping it looked like the
  /// download never saved.
  Future<void> _download([StorageTier? tier]) async {
    setState(() => _isDownloading = true);
    try {
      final DownloadOutcome outcome =
          await ref.read(configuredDownloadProvider)(
            _wallpaper,
            tier: tier,
            chooseVolume: ({required bool offerSdCard}) =>
                chooseDownloadVolume(context, offerSdCard: offerSdCard),
          );
      _reportDownload(outcome);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  /// A dismissed folder chooser is silent: the user stopped, did not fail.
  void _reportDownload(DownloadOutcome outcome) {
    if (!mounted) return;
    switch (outcome) {
      case DownloadOutcome.saved:
        refreshDownloads(ref);
        _showResult(AppLocalizations.of(context).detailDownloadSuccess);
      case DownloadOutcome.folderUnavailable:
        _showResult(
          AppLocalizations.of(context).detailDownloadFolderUnavailable,
          kind: ToastKind.failure,
        );
      case DownloadOutcome.failed:
        _showResult(
          AppLocalizations.of(context).detailDownloadFailure,
          kind: ToastKind.failure,
        );
      case DownloadOutcome.cancelled:
        break;
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
      if (mounted) {
        _showResult(
          AppLocalizations.of(context).detailShareFailure,
          kind: ToastKind.failure,
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  /// Pushes the listing behind a tag or an uploader, rather than replacing this
  /// one, so Back returns to the wallpaper the link was printed on and the
  /// browse tabs are left exactly as the user had them.
  void _follow(WallpaperLink link) {
    unawaited(
      context.pushNamed(
        TelaRoutes.linkedListingName,
        extra: LinkedListingArgs(link: link, seed: widget.originFilters),
      ),
    );
  }

  /// Hands a URL — a wallpaper's source or its Wallhaven page — to the device
  /// browser, saying so only when nothing can open it.
  Future<void> _openLink(Uri url) async {
    try {
      await ref.read(externalLinkProvider).open(url);
    } on ExternalLinkFailure {
      if (mounted) {
        _showResult(
          AppLocalizations.of(context).detailLinkFailure,
          kind: ToastKind.failure,
        );
      }
    }
  }

  void _showResult(String message, {ToastKind kind = ToastKind.success}) {
    showTelaToast(ScaffoldMessenger.of(context), message, kind: kind);
  }

  /// Asks before blocking a tag — every future search silently excludes it,
  /// which is not a thing to do on a single stray long press. Mirrors the
  /// download-history "Remove from history?" dialog: say plainly what will
  /// happen, and that it can be undone.
  Future<void> _confirmBlockTag(WallpaperTag tag) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.detailTagBlockTitle),
        content: Text(l10n.detailTagBlockBody(tag.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.detailTagBlock),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await _blockTag(tag);
  }

  Future<void> _blockTag(WallpaperTag tag) async {
    await ref.read(tagBlocklistRepositoryProvider).block(tag);
    refreshBlockedTags(ref);
    if (mounted) {
      _showResult(AppLocalizations.of(context).detailTagBlocked(tag.name));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<WallpaperDetails> details = ref.watch(
      wallpaperDetailsProvider(_wallpaper.id),
    );
    final bool expanded = MediaQuery.sizeOf(context).width >= _expandedWidth;
    return Scaffold(
      // No title: the resolution that used to sit here is a spec, not a name,
      // and it already has a tile in the Details grid — a title bar reading
      // "2880x1800" labelled the screen with a number. The image is the
      // subject, so the bar carries only the back affordance and the actions.
      appBar: AppBar(
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
      _adjustButton(l10n),
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

  /// The wallpaper, swipeable across the whole shelf without leaving Detail.
  ///
  /// A [PageView] over the same session the fullscreen viewer pages, so a swipe
  /// here moves the selection and the metadata, actions, and Set button below
  /// all follow. Chevrons offer the same step for a thumb that would rather
  /// tap, each shown only while there is a loaded neighbour to reach.
  Widget _preview() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        PageView.builder(
          controller: _pages,
          onPageChanged: _onPageTurned,
          itemCount: _gallery.items.length,
          itemBuilder: (BuildContext context, int index) => _previewPage(index),
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
        if (_gallery.canSelectPrevious)
          _pageChevron(
            key: const Key('detail-previous'),
            alignment: Alignment.centerLeft,
            icon: Icons.chevron_left,
            tooltip: AppLocalizations.of(context).galleryPrevious,
            onPressed: () => _turnTo(_gallery.selectedIndex - 1),
          ),
        if (_gallery.canSelectNext)
          _pageChevron(
            key: const Key('detail-next'),
            alignment: Alignment.centerRight,
            icon: Icons.chevron_right,
            tooltip: AppLocalizations.of(context).galleryNext,
            onPressed: () => _turnTo(_gallery.selectedIndex + 1),
          ),
      ],
    );
  }

  /// One page of the preview pager.
  ///
  /// Only the selected page carries the shared-element [Hero]: the grid flies
  /// one tile in, and a second Hero whose tag matches another grid tile would
  /// be the "multiple heroes" crash, so the neighbours the pager pre-builds
  /// stay heroless until they are the one on screen.
  Widget _previewPage(int index) {
    final Wallpaper wallpaper = _gallery.items[index];
    return ProgressiveWallpaperPreview(
      wallpaper: wallpaper,
      fillLetterbox: true,
      heroTag: index == _gallery.selectedIndex
          ? shelfHeroTag(_gallery.identity, wallpaper.id, index)
          : null,
    );
  }

  Widget _pageChevron({
    required Key key,
    required Alignment alignment,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: IconButton.filledTonal(
          key: key,
          onPressed: onPressed,
          tooltip: tooltip,
          icon: Icon(icon),
        ),
      ),
    );
  }

  /// A swipe (or a chevron's animation) landed on [index]: move the session,
  /// which reselect-ignores a no-op and rebinds everything else.
  void _onPageTurned(int index) => _gallery.select(index);

  /// Steps the pager to [index], animating unless the platform asked not to —
  /// where a jump keeps the step instant and testable.
  void _turnTo(int index) {
    if (index < 0 || index >= _gallery.items.length) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(index);
      return;
    }
    unawaited(
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      ),
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
          _adjustButton(l10n),
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
      data: (WallpaperDetails value) => WallpaperMetadata(
        details: value,
        onFollow: _follow,
        onBlockTag: _confirmBlockTag,
        onOpenLink: _openLink,
      ),
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

  /// Shown for every purity now that tela has its own in-app cropper: [_adjust]
  /// routes explicit wallpapers there rather than to the OEM editor, so the
  /// button no longer needs to be withheld to honour [mayExportBitmap].
  Widget _adjustButton(AppLocalizations l10n) {
    return IconButton(
      key: const Key('detail-adjust'),
      onPressed: _isAdjusting ? null : _adjust,
      tooltip: l10n.detailAdjust,
      icon: _isAdjusting
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.crop_outlined),
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
