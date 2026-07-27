import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/gradient_app_bar.dart';
import 'package:tela/core/ui/justified_wallpaper_grid.dart';
import 'package:tela/core/ui/selection_shelf.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';
import 'package:tela/core/ui/wallpaper_grid_skeleton.dart';
import 'package:tela/core/ui/wallpaper_selection.dart';
import 'package:tela/core/ui/wallpaper_source_badge.dart';
import 'package:tela/core/ui/wallpaper_source_labels_scope.dart';
import 'package:tela/core/ui/wallpaper_status_view.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/features/private_library/private_secure_access.dart';

/// The app-private tier, which nothing but tela can open.
///
/// Holds `FLAG_SECURE` while on screen and satisfies the app-lock before it
/// lists anything — both through [PrivateSecureAccess], which the
/// fullscreen viewer shares so the protection survives the whole private flow.
/// Tapping a tile opens that image in the secure viewer. A long press enters
/// multi-select — the same rule the other library shelves follow — and deleting
/// one file is the batch delete at a count of one, so the permanence warning is
/// worded once and shown for both.
class PrivateLibraryScreen extends ConsumerStatefulWidget {
  /// Creates the private library.
  const PrivateLibraryScreen({super.key});

  @override
  ConsumerState<PrivateLibraryScreen> createState() =>
      _PrivateLibraryScreenState();
}

class _PrivateLibraryScreenState extends ConsumerState<PrivateLibraryScreen>
    with PrivateSecureAccess<PrivateLibraryScreen> {
  @override
  void initState() {
    super.initState();
    beginPrivateAccess();
  }

  @override
  void dispose() {
    endPrivateAccess();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SelectionShelfScope(
      child: Scaffold(
        appBar: GradientAppBar(
          toolbarHeight: 72,
          title: Text(
            l10n.privateLibraryTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          actions: const <Widget>[SelectModeButton(), SizedBox(width: 8)],
        ),
        body: _body(context, l10n),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    if (isCheckingLock) return const Center(child: CircularProgressIndicator());
    if (!isUnlocked) return _locked(l10n);
    return ref
        .watch(privateImagesProvider)
        .when(
          data: (List<PrivateImage> stored) => _grid(context, l10n, stored),
          loading: () => const WallpaperGridSkeleton(),
          error: (Object error, StackTrace stackTrace) => WallpaperStatusView(
            icon: Icons.error_outline,
            message: l10n.privateLibraryUnavailable,
          ),
        );
  }

  /// What a failed or dismissed prompt leaves behind: a way to try again, and
  /// nothing else. No count, no thumbnails, no hint of what is in there.
  Widget _locked(AppLocalizations l10n) {
    return WallpaperStatusView(
      icon: Icons.lock_outline,
      message: l10n.privateLibraryLocked,
      actionLabel: l10n.privateLibraryUnlock,
      onAction: authenticate,
    );
  }

  Widget _grid(
    BuildContext context,
    AppLocalizations l10n,
    List<PrivateImage> stored,
  ) {
    if (stored.isEmpty) {
      return WallpaperStatusView(
        icon: Icons.lock_open_outlined,
        message: l10n.privateLibraryEmpty,
      );
    }
    // Rows keyed to each file's real aspect ratio now that the native listing
    // decodes its bounds; a corrupt file with none falls back square.
    return SelectionShelf(
      itemIds: <String>[for (final PrivateImage image in stored) image.ref.key],
      // Deleting is the only batch that means anything here. These files are
      // already on the device, so there is nothing to download, and favoriting
      // is a Wallhaven-wallpaper idea the private tier deliberately has no part
      // in — a favorite would be a second, unlocked index of what is in here.
      actions: <SelectionAction>[
        SelectionAction(
          icon: Icons.delete_outline,
          label: l10n.privateLibraryDelete,
          run: _deleteSelected,
        ),
      ],
      child: JustifiedWallpaperGrid(
        itemCount: stored.length,
        aspectRatioOf: (int index) => stored[index].aspectRatio ?? 1,
        itemBuilder: (BuildContext context, int index, double _, double _) =>
            _tile(context, stored, index),
      ),
    );
  }

  Widget _tile(BuildContext context, List<PrivateImage> stored, int index) {
    final gestures = selectableTileGestures(
      context: context,
      wallpaperKey: stored[index].ref.key,
      onOpen: () => _open(context, stored, index),
      longPressSelects: true,
    );
    return _PrivateTile(
      image: stored[index],
      position: index,
      onTap: gestures.onTap,
      onLongPress: gestures.onLongPress,
    );
  }

  /// Opens the whole private tier in the secure viewer, on the tapped image.
  ///
  /// The session is the complete local list, so it never pages — like Favorites
  /// and History. Its creator disposes it when the viewer returns.
  void _open(BuildContext context, List<PrivateImage> stored, int index) {
    unawaited(_pushViewer(context, stored, index));
  }

  Future<void> _pushViewer(
    BuildContext context,
    List<PrivateImage> stored,
    int index,
  ) async {
    final GallerySessionController<PrivateImage> session =
        GallerySessionController<PrivateImage>(
          identity: 'private-library',
          items: stored,
          initialIndex: index,
          itemKey: (PrivateImage image) => image.ref.key,
        );
    try {
      await context.pushNamed<void>(
        TelaRoutes.privateViewerName,
        extra: session,
      );
    } finally {
      session.dispose();
    }
  }

  /// Confirms, then deletes every ticked file, reporting what actually went.
  ///
  /// Answers false on a declined confirmation so the ticks survive it — the
  /// user cancelled the deletion, not the selection.
  Future<bool> _deleteSelected(List<String> keys) async {
    if (keys.isEmpty) return false;
    if (!await _confirmDelete(keys.length)) return false;
    if (!mounted) return false;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int deleted = await _deleteAll(keys);
    ref.invalidate(privateImagesProvider);
    if (mounted) _show(_deleteOutcome(l10n, deleted, keys.length));
    return true;
  }

  /// One at a time, counting the ones that failed rather than hiding them:
  /// "deleted 3 of 5" and "deleted 5" are different facts about the device.
  ///
  /// Routes through [deleteDownloadProvider] — the same hard-delete path the
  /// download history and detail screen use (J). For the app-private tier that
  /// is a file delete plus a history `forget` that no-ops, since nothing
  /// private is ever recorded there.
  Future<int> _deleteAll(List<String> keys) async {
    final Map<String, Uri> locations = _locationsFor(keys);
    int deleted = 0;
    for (final String key in keys) {
      final Uri? location = locations[key];
      if (location != null && await _deleteOne(location)) deleted++;
    }
    return deleted;
  }

  /// The on-disk location of each selected key, from the loaded listing.
  Map<String, Uri> _locationsFor(List<String> keys) {
    final List<PrivateImage> stored =
        ref.read(privateImagesProvider).value ?? const <PrivateImage>[];
    final Set<String> wanted = keys.toSet();
    return <String, Uri>{
      for (final PrivateImage image in stored)
        if (wanted.contains(image.ref.key)) image.ref.key: image.location,
    };
  }

  Future<bool> _deleteOne(Uri location) async {
    try {
      await ref.read(deleteDownloadProvider)(
        // An app-private image has no history row, by design.
        ref: null,
        tier: StorageTier.appPrivate,
        location: location,
      );
      return true;
    } on ImageStoreFailure {
      return false;
    }
  }

  String _deleteOutcome(AppLocalizations l10n, int deleted, int total) {
    if (deleted == total) return l10n.privateLibraryDeleteDone(total);
    return l10n.privateLibraryDeletePartial(deleted, total, total - deleted);
  }

  Future<bool> _confirmDelete(int count) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.privateLibraryDeleteTitleMany(count)),
        content: Text(l10n.privateLibraryDeleteBodyMany(count)),
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
    return confirmed ?? false;
  }

  void _show(String message, {ToastKind kind = ToastKind.success}) {
    showTelaToast(ScaffoldMessenger.of(context), message, kind: kind);
  }
}

/// One app-private file, decoded from disk rather than from the network.
class _PrivateTile extends StatelessWidget {
  const _PrivateTile({
    required this.image,
    required this.position,
    required this.onTap,
    required this.onLongPress,
  });

  final PrivateImage image;
  final int position;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      button: true,
      image: true,
      // Null outside selection so the tile is not announced as "not selected"
      // in ordinary browsing — the same rule WallpaperTile follows.
      selected: WallpaperSelectionScope.isActive(context)
          ? WallpaperSelectionScope.isSelected(context, image.ref.key)
          : null,
      label: l10n.privateLibraryImageLabel(image.ref.id),
      child: Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(wallpaperTileRadius),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        // Sized by the justified row, not here: the row already derived its
        // height from this same ratio (a corrupt file's missing one falls back
        // square there too), and a self-measuring tile would fight it.
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          // The wash-and-tick the shelf shares with every other selectable
          // grid; without it a ticked private tile looked identical to an
          // untouched one.
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _thumbnail(context),
              ?_badge(context),
              WallpaperSelectionOverlay(wallpaperKey: image.ref.key),
            ],
          ),
        ),
      ),
    );
  }

  /// The source pill, in the same corner every other shelf puts it.
  ///
  /// Unconditional here, unlike `WallpaperTile`'s opt-in flag: this grid is
  /// mixed by nature — one folder holding whatever any source sent to the
  /// private tier — so there is no single-source case for it to say nothing in.
  ///
  /// Null when no `WallpaperSourceLabelsScope` names the source: a file written
  /// by a build whose source this one has since retired draws no badge rather
  /// than a raw lowercase id.
  Widget? _badge(BuildContext context) {
    final String? name = WallpaperSourceLabelsScope.labelFor(
      context,
      image.ref.source.value,
    );
    if (name == null) return null;
    return Positioned(
      bottom: 6,
      left: 6,
      child: WallpaperSourceBadge(sourceName: name),
    );
  }

  /// Decodes at roughly tile width, not at the source's 6K. The decoded
  /// thumbnail flies into the secure viewer under a shelf-scoped Hero tag.
  Widget _thumbnail(BuildContext context) {
    final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return Hero(
      tag: shelfHeroTag('private-library', image.ref.key, position),
      child: Container(
        foregroundDecoration: wallpaperTileEdge(Theme.of(context).colorScheme),
        child: Image.file(
          File.fromUri(image.location),
          fit: BoxFit.cover,
          cacheWidth: (_tileWidthDip * devicePixelRatio).round(),
          errorBuilder:
              (BuildContext context, Object error, StackTrace? trace) =>
                  const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    );
  }

  static const double _tileWidthDip = 200;
}
