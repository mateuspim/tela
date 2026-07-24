import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/delete_download_action.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/gallery_zoom_controller.dart';
import 'package:tela/core/ui/immersive_gallery_viewer.dart';
import 'package:tela/core/ui/immersive_system_ui.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/core/ui/wallpaper_target_sheet.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/features/downloads/download_gallery_source.dart';

/// The immersive, local-first viewer for one download-history session.
///
/// Unlike Detail, its primary action is Set wallpaper — History exists to set a
/// file again — with Home/Lock/Both behind it, and it reuses `ApplyDownload` so
/// a deleted file still falls back to Wallhaven. Set, the missing badge, and
/// "remove from history" all follow the item the viewer is currently showing,
/// never the tile that opened it.
class DownloadImmersiveSession extends ConsumerStatefulWidget {
  /// Creates the viewer over an already-loaded history [session].
  const DownloadImmersiveSession({
    required this.session,
    this.systemUi = const FlutterImmersiveSystemUi(),
    super.key,
  });

  /// The complete, local history snapshot, positioned on the tapped record.
  final GallerySessionController<DownloadRecord> session;

  /// The Android system-chrome seam, injectable for focused tests.
  final ImmersiveSystemUi systemUi;

  @override
  ConsumerState<DownloadImmersiveSession> createState() =>
      _DownloadImmersiveSessionState();
}

class _DownloadImmersiveSessionState
    extends ConsumerState<DownloadImmersiveSession> {
  late final GalleryZoomController _zoomController;
  late int _selectedIndex;
  bool _isApplying = false;

  DownloadRecord get _record => widget.session.selectedItem;

  @override
  void initState() {
    super.initState();
    _zoomController = GalleryZoomController();
    _selectedIndex = widget.session.selectedIndex;
    widget.session.addListener(_sessionChanged);
  }

  /// Resets zoom only when the selected record actually changes, so nothing
  /// else can fling the current image back to fitted scale.
  void _sessionChanged() {
    if (widget.session.selectedIndex != _selectedIndex) {
      _selectedIndex = widget.session.selectedIndex;
      _zoomController.reset();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    _zoomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final GallerySessionController<DownloadRecord> session = widget.session;
    final DownloadRecord record = _record;
    final bool missing = _isMissing(record);
    // A Scaffold gives the viewer's Set/apply feedback a ScaffoldMessenger to
    // land on — the immersive surface is a bare Material, not a Scaffold.
    return Scaffold(
      backgroundColor: Colors.black,
      body: ImmersiveGalleryViewer(
        aspectRatio:
            record.wallpaper.resolution.width /
            record.wallpaper.resolution.height,
        semanticsLabel: l10n.detailPreviewLabel(record.wallpaper.id),
        source: DownloadGallerySource(
          record: record,
          cache: ref.read(localPreviewCacheProvider),
        ),
        position: session.selectedIndex + 1,
        itemCount: session.items.length,
        onPrevious: session.canSelectPrevious ? session.selectPrevious : null,
        onNext: session.canSelectNext ? session.selectNext : null,
        zoomController: _zoomController,
        systemUi: widget.systemUi,
        heroTag: shelfHeroTag(
          session.identity,
          record.wallpaper.ref.key,
          session.selectedIndex,
        ),
        barActions: <Widget>[_setButton(l10n)],
        actions: <Widget>[_overflow(l10n)],
        statusOverlay: missing ? _missingBadge(l10n) : null,
        // pop(), never maybePop(): the viewer's own PopScope defers to
        // _exitFullscreen, so consulting it from inside onClose is a cycle
        // that leaves the route standing.
        onClose: () async => Navigator.of(context).pop(),
      ),
    );
  }

  /// True when the shown record's file is gone, from the same probe the grid
  /// badges with — so the viewer and the grid agree on which rows are missing.
  bool _isMissing(DownloadRecord record) {
    final Set<String> missing =
        ref.watch(missingDownloadsProvider).value ?? const <String>{};
    return missing.contains(record.wallpaper.ref.key);
  }

  Widget _setButton(AppLocalizations l10n) {
    return FilledButton.icon(
      key: const Key('download-viewer-set'),
      onPressed: _isApplying ? null : _chooseTarget,
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      icon: _isApplying
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.wallpaper_outlined),
      label: Text(l10n.detailSetWallpaper),
    );
  }

  Widget _overflow(AppLocalizations l10n) {
    return PopupMenuButton<void>(
      key: const Key('download-viewer-overflow'),
      tooltip: l10n.galleryMoreActions,
      icon: const Icon(Icons.more_vert, color: Colors.white),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<void>>[
        PopupMenuItem<void>(
          onTap: _confirmForget,
          child: Text(l10n.downloadHistoryForgetMenu),
        ),
        PopupMenuItem<void>(
          key: const Key('download-viewer-delete'),
          onTap: _deleteFromDevice,
          child: Text(l10n.downloadDeleteMenu),
        ),
      ],
    );
  }

  /// Hard-deletes the shown record — the file and its history row — then leaves
  /// the viewer, since the record it was showing is gone.
  ///
  /// Sits beside "Remove from history" on purpose: the two are the whole point
  /// of keeping both, one dropping the list row and one deleting the file. A
  /// declined system prompt or a failure leaves the viewer where it was.
  Future<void> _deleteFromDevice() async {
    final DownloadRecord record = _record;
    final bool deleted = await confirmAndDeleteDownload(
      context: context,
      ref: ref,
      wallpaper: record.wallpaper.ref,
      tier: record.tier,
      location: record.location,
    );
    if (!deleted || !mounted) return;
    ref.invalidate(recentDownloadsProvider);
    await Navigator.of(context).maybePop();
  }

  Widget _missingBadge(AppLocalizations l10n) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.cloud_download_outlined,
              size: 18,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              l10n.downloadViewerMissing,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  /// Chooses a target and applies the shown record, reading its file first.
  Future<void> _chooseTarget() async {
    final DownloadRecord record = _record;
    final WallpaperTarget? target = await chooseWallpaperTarget(context);
    if (target == null || !mounted) return;
    setState(() => _isApplying = true);
    try {
      await ref.read(applyDownloadProvider)(record, target);
      if (mounted) _show(AppLocalizations.of(context).detailApplySuccess);
    } on WallpaperApplyFailure {
      if (mounted) {
        _show(
          AppLocalizations.of(context).detailApplyFailure,
          kind: ToastKind.failure,
        );
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  /// Forgets the shown record after the same file-stays confirmation the grid
  /// uses, then leaves the viewer — the row it was showing is gone.
  Future<void> _confirmForget() async {
    final DownloadRecord record = _record;
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
    if (!(confirmed ?? false) || !mounted) return;
    await ref.read(downloadHistoryProvider).forget(record.wallpaper.ref);
    ref.invalidate(recentDownloadsProvider);
    if (mounted) await Navigator.of(context).maybePop();
  }

  void _show(String message, {ToastKind kind = ToastKind.success}) {
    showTelaToast(ScaffoldMessenger.of(context), message, kind: kind);
  }
}
