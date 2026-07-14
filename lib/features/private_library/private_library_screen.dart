import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/ports/screen_guard.dart';
import 'package:tela/features/private_library/private_library_providers.dart';

/// The app-private tier, which nothing but tela can open.
///
/// Holds `FLAG_SECURE` for as long as it is on screen: no screenshots, no
/// screen recording, and no thumbnail in the app switcher. The flag belongs to
/// the window rather than to a route, so this screen takes it on the way in and
/// gives it back on the way out.
class PrivateLibraryScreen extends ConsumerStatefulWidget {
  /// Creates the private library.
  const PrivateLibraryScreen({super.key});

  @override
  ConsumerState<PrivateLibraryScreen> createState() =>
      _PrivateLibraryScreenState();
}

class _PrivateLibraryScreenState extends ConsumerState<PrivateLibraryScreen> {
  /// Held in a field rather than re-read on the way out: Riverpod forbids
  /// `ref.read` in `dispose`, and the flag has to be given back exactly when
  /// this screen goes away — there is no later chance to do it.
  late final ScreenGuard _screenGuard;

  @override
  void initState() {
    super.initState();
    _screenGuard = ref.read(screenGuardProvider);
    // Before the first frame: a thumbnail can be captured the moment the route
    // is on screen, so asking for the flag later is asking too late.
    unawaited(_screenGuard.setSecure(secure: true));
  }

  @override
  void dispose() {
    unawaited(_screenGuard.setSecure(secure: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<PrivateImage>> images = ref.watch(
      privateImagesProvider,
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.privateLibraryTitle)),
      body: images.when(
        data: (List<PrivateImage> stored) => _grid(context, l10n, stored),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) =>
            Center(child: Text(l10n.privateLibraryUnavailable)),
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    AppLocalizations l10n,
    List<PrivateImage> stored,
  ) {
    if (stored.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(l10n.privateLibraryEmpty, textAlign: TextAlign.center),
        ),
      );
    }
    // Square tiles, not the masonry the other grids use: masonry packs by each
    // image's aspect ratio, and a file on disk has no known ratio until it is
    // decoded. A browse tile gets its shape from Wallhaven's metadata; this one
    // has none to get.
    return GridView.count(
      crossAxisCount: wallpaperGridColumns(context),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      padding: const EdgeInsets.all(8),
      children: <Widget>[
        for (final PrivateImage image in stored)
          _PrivateTile(image: image, onDelete: () => _confirmDelete(image)),
      ],
    );
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
  const _PrivateTile({required this.image, required this.onDelete});

  final PrivateImage image;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      image: true,
      label: l10n.privateLibraryImageLabel(image.id),
      child: Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: InkWell(
          onLongPress: onDelete,
          child: _thumbnail(context),
        ),
      ),
    );
  }

  /// Decodes at roughly tile width, not at the source's 6K.
  Widget _thumbnail(BuildContext context) {
    final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return Image.file(
      File.fromUri(image.location),
      fit: BoxFit.cover,
      cacheWidth: (_tileWidthDip * devicePixelRatio).round(),
      errorBuilder: (BuildContext context, Object error, StackTrace? trace) =>
          const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }

  static const double _tileWidthDip = 200;
}
