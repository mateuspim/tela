import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';
import 'package:tela/core/ui/wallpaper_status_view.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/features/private_library/private_secure_access.dart';

/// The app-private tier, which nothing but tela can open.
///
/// Holds `FLAG_SECURE` while on screen and satisfies the app-lock before it
/// lists anything — both through [PrivateSecureAccess], which the
/// fullscreen viewer shares so the protection survives the whole private flow.
/// Tapping a tile opens that image in the secure viewer; a long press still
/// offers to delete the file.
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
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Text(
          l10n.privateLibraryTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      body: _body(context, l10n),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    if (isCheckingLock) return const Center(child: CircularProgressIndicator());
    if (!isUnlocked) return _locked(l10n);
    return ref
        .watch(privateImagesProvider)
        .when(
          data: (List<PrivateImage> stored) => _grid(context, l10n, stored),
          loading: () => const Center(child: CircularProgressIndicator()),
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
    // Masonry keyed to each file's real aspect ratio now that the native
    // listing decodes its bounds; a corrupt file with none falls back square.
    return MasonryGridView.count(
      crossAxisCount: wallpaperGridColumns(context),
      mainAxisSpacing: wallpaperGridSpacing,
      crossAxisSpacing: wallpaperGridSpacing,
      padding: wallpaperGridPadding(context),
      itemCount: stored.length,
      itemBuilder: (BuildContext context, int index) => _PrivateTile(
        image: stored[index],
        position: index,
        onTap: () => _open(context, stored, index),
        onDelete: () => _confirmDelete(stored[index]),
      ),
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
          itemKey: (PrivateImage image) => image.id,
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

  Future<void> _confirmDelete(PrivateImage image) async {
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
    if (confirmed ?? false) await _delete(image);
  }

  Future<void> _delete(PrivateImage image) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      await ref.read(imageStoreProvider).deletePrivateImage(image.id);
      ref.invalidate(privateImagesProvider);
    } on ImageStoreFailure {
      if (mounted) _show(l10n.privateLibraryDeleteFailure);
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// One app-private file, decoded from disk rather than from the network.
class _PrivateTile extends StatelessWidget {
  const _PrivateTile({
    required this.image,
    required this.position,
    required this.onTap,
    required this.onDelete,
  });

  final PrivateImage image;
  final int position;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      button: true,
      image: true,
      label: l10n.privateLibraryImageLabel(image.id),
      child: Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(wallpaperTileRadius),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: onTap,
          onLongPress: onDelete,
          // A corrupt file has no known ratio; a square keeps the grid rhythm.
          child: AspectRatio(
            aspectRatio: image.aspectRatio ?? 1,
            child: _thumbnail(context),
          ),
        ),
      ),
    );
  }

  /// Decodes at roughly tile width, not at the source's 6K. The decoded
  /// thumbnail flies into the secure viewer under a shelf-scoped Hero tag.
  Widget _thumbnail(BuildContext context) {
    final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return Hero(
      tag: shelfHeroTag('private-library', image.id, position),
      child: Image.file(
        File.fromUri(image.location),
        fit: BoxFit.cover,
        cacheWidth: (_tileWidthDip * devicePixelRatio).round(),
        errorBuilder: (BuildContext context, Object error, StackTrace? trace) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      ),
    );
  }

  static const double _tileWidthDip = 200;
}
