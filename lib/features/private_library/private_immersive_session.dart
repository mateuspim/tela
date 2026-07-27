import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/move_to_private_action.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/gallery_zoom_controller.dart';
import 'package:tela/core/ui/immersive_gallery_viewer.dart';
import 'package:tela/core/ui/immersive_system_ui.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/core/ui/wallpaper_status_view.dart';
import 'package:tela/core/ui/wallpaper_target_sheet.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/features/private_library/private_gallery_source.dart';
import 'package:tela/features/private_library/private_secure_access.dart';

/// The secure, local-only fullscreen viewer for the app-private tier.
///
/// It holds `FLAG_SECURE` and satisfies the app-lock independently of the grid
/// (see [PrivateSecureAccess]), so no screenshot, recording, or app-switcher
/// thumbnail of an explicit wallpaper is possible, and swiping between private
/// images re-runs neither. Its primary action is Set wallpaper; delete is an
/// explicit, confirmed action that advances to the nearest remaining image and
/// closes to the empty state when none are left. There is no sharing here, by
/// design — a private image's pixels never leave the device.
class PrivateImmersiveSession extends ConsumerStatefulWidget {
  /// Creates the viewer over an already-loaded private [session].
  const PrivateImmersiveSession({
    required this.session,
    this.systemUi = const FlutterImmersiveSystemUi(),
    super.key,
  });

  /// The complete, local private snapshot, positioned on the tapped image.
  final GallerySessionController<PrivateImage> session;

  /// The Android system-chrome seam, injectable for focused tests.
  final ImmersiveSystemUi systemUi;

  @override
  ConsumerState<PrivateImmersiveSession> createState() =>
      _PrivateImmersiveSessionState();
}

class _PrivateImmersiveSessionState
    extends ConsumerState<PrivateImmersiveSession>
    with PrivateSecureAccess<PrivateImmersiveSession> {
  late final GalleryZoomController _zoomController;
  late int _selectedIndex;
  bool _isApplying = false;

  PrivateImage get _image => widget.session.selectedItem;

  @override
  void initState() {
    super.initState();
    _zoomController = GalleryZoomController();
    _selectedIndex = widget.session.selectedIndex;
    widget.session.addListener(_sessionChanged);
    beginPrivateAccess();
  }

  /// Resets zoom only when the selected image actually changes.
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
    endPrivateAccess();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // FLAG_SECURE is already held; the black canvas keeps the contents off
    // screen until the lock passes, and covers the frame after a delete empties
    // the session and before the pop lands.
    if (isCheckingLock) return _canvas(const CircularProgressIndicator());
    if (!isUnlocked) return _canvas(_locked(l10n));
    if (widget.session.items.isEmpty) return _canvas(null);
    return _viewer(l10n);
  }

  Widget _viewer(AppLocalizations l10n) {
    final GallerySessionController<PrivateImage> session = widget.session;
    final PrivateImage image = _image;
    return Scaffold(
      backgroundColor: Colors.black,
      body: ImmersiveGalleryViewer(
        // A corrupt file has no known ratio; a square canvas frames its safe
        // broken-image state without dividing by an unknown dimension.
        aspectRatio: image.aspectRatio ?? 1,
        semanticsLabel: l10n.privateLibraryImageLabel(image.ref.id),
        source: PrivateGallerySource(
          image: image,
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
          image.ref.key,
          session.selectedIndex,
        ),
        barActions: <Widget>[_setButton(l10n)],
        actions: <Widget>[_moveOutButton(l10n), _deleteButton(l10n)],
        // pop(), never maybePop(): the viewer's own PopScope defers to
        // _exitFullscreen, so consulting it from inside onClose is a cycle
        // that leaves the route standing. See the delete-to-empty exit below.
        onClose: () async => Navigator.of(context).pop(),
      ),
    );
  }

  Widget _canvas(Widget? child) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: child == null ? null : Center(child: child),
    );
  }

  Widget _locked(AppLocalizations l10n) {
    return WallpaperStatusView(
      icon: Icons.lock_outline,
      message: l10n.privateLibraryLocked,
      actionLabel: l10n.privateLibraryUnlock,
      onAction: authenticate,
    );
  }

  Widget _setButton(AppLocalizations l10n) {
    return FilledButton.icon(
      key: const Key('private-viewer-set'),
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

  /// The way back out of this tier, and the only one there is.
  ///
  /// A second icon rather than an overflow menu: two actions do not earn a
  /// menu, and the delete beside it is the one this viewer has always shown.
  Widget _moveOutButton(AppLocalizations l10n) {
    return IconButton.filledTonal(
      key: const Key('private-viewer-move-out'),
      onPressed: _moveOut,
      tooltip: l10n.moveOutOfPrivateAction,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      icon: const Icon(Icons.lock_open_outlined),
    );
  }

  Widget _deleteButton(AppLocalizations l10n) {
    return IconButton.filledTonal(
      key: const Key('private-viewer-delete'),
      onPressed: _confirmDelete,
      tooltip: l10n.privateLibraryDelete,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      icon: const Icon(Icons.delete_outline),
    );
  }

  /// Chooses a target and applies the shown private file.
  Future<void> _chooseTarget() async {
    final PrivateImage image = _image;
    final WallpaperTarget? target = await chooseWallpaperTarget(context);
    if (target == null || !mounted) return;
    setState(() => _isApplying = true);
    try {
      await ref.read(applyPrivateImageProvider)(image, target);
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

  /// Deletes the shown file after the same confirmation the grid uses, then
  /// advances to the nearest remaining image or closes to the empty state.
  /// Moves the shown image out to the files folder, then leaves it behind.
  ///
  /// Advances or pops exactly as a delete does — from this viewer's point of
  /// view a moved image is gone, and it must not stay on a `FLAG_SECURE`
  /// canvas showing a file that is no longer private.
  Future<void> _moveOut() async {
    final PrivateImage image = _image;
    final bool moved = await confirmAndMoveOutOfPrivate(
      context: context,
      ref: ref,
      images: <PrivateImage>[image],
    );
    if (!moved || !mounted) return;
    ref.invalidate(privateImagesProvider);
    _leaveShownImage();
  }

  Future<void> _confirmDelete() async {
    final PrivateImage image = _image;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.privateLibraryDeleteTitle),
        content: Text(l10n.privateLibraryDeleteBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.privateLibraryDelete),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    await _delete(image);
  }

  Future<void> _delete(PrivateImage image) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      await ref.read(deleteDownloadProvider)(
        // An app-private image has no history row, by design.
        ref: null,
        tier: StorageTier.appPrivate,
        location: image.location,
      );
    } on ImageStoreFailure {
      if (mounted) {
        _show(l10n.privateLibraryDeleteFailure, kind: ToastKind.failure);
      }
      return;
    }
    // The grid behind the viewer reads this provider; refresh it so it agrees
    // whether we advance or pop back to it.
    ref.invalidate(privateImagesProvider);
    if (!mounted) return;
    _leaveShownImage();
  }

  /// Drops the shown image from the session and moves on, or leaves when it was
  /// the last one.
  ///
  /// Shared by the delete and the move-out: both make the shown image cease to
  /// be something this viewer may show, and only the reason differs.
  void _leaveShownImage() {
    final bool remains = widget.session.removeSelected();
    if (!remains) {
      // Unconditional pop: the immersive surface owns a PopScope that gates the
      // back gesture, and this exit is ours to make outright — nothing is left
      // to show, so return to the grid's empty state.
      Navigator.of(context).pop();
      return;
    }
    _zoomController.reset();
    setState(() {});
  }

  void _show(String message, {ToastKind kind = ToastKind.success}) {
    showTelaToast(ScaffoldMessenger.of(context), message, kind: kind);
  }
}
