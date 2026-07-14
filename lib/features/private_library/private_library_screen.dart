import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';
import 'package:tela/core/ui/wallpaper_status_view.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/ports/app_lock.dart';
import 'package:tela/domain/ports/screen_guard.dart';

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

  /// False until the lock has been satisfied. Nothing is listed before it.
  bool _unlocked = false;

  /// True while the lock is being resolved or the system prompt is up.
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _screenGuard = ref.read(screenGuardProvider);
    // Before the first frame: a thumbnail can be captured the moment the route
    // is on screen, so asking for the flag later is asking too late.
    unawaited(_screenGuard.setSecure(secure: true));
    unawaited(_unlock());
  }

  @override
  void dispose() {
    unawaited(_screenGuard.setSecure(secure: false));
    super.dispose();
  }

  /// Resolves the lock before anything is listed.
  ///
  /// The gate lives in the screen rather than on the settings tile that opens
  /// it, because a route can be reached more ways than one — gating the button
  /// would leave a deep link to `/private` walking straight past it.
  ///
  /// **It fails closed.** If the lock is on, the only way past is a prompt that
  /// passes; anything else lands on [_locked]. It used to step aside when
  /// `AppLock.isAvailable()` said no, to avoid trapping the owner outside their
  /// own files on a device that cannot ask anything — but `isAvailable` cannot
  /// tell "this device has no credentials" apart from "the sensor is locked out
  /// for the next 30 seconds", and it reports both as false. On a device whose
  /// only credential is a fingerprint, that turned five bad reads into an open
  /// door: found on hardware, 2026-07-14. The owner's way back in is the
  /// Settings switch, which stays operable precisely for this (`AppLockSwitch`)
  /// — a lock you can turn off is not a trap, but a lock that opens itself is
  /// not a lock.
  Future<void> _unlock() async {
    final bool locked = await ref
        .read(settingsRepositoryProvider)
        .isPrivateLibraryLocked();
    if (!locked) {
      if (mounted) setState(() => _pass(unlocked: true));
      return;
    }
    await _authenticate();
  }

  /// Only [AppLockOutcome.passed] opens the library — including over
  /// [AppLockOutcome.unavailable], which is the whole point. A device that
  /// cannot ask is not a device that has proven anything; the owner's way back
  /// in is to switch the lock off in Settings, which is the one place that
  /// outcome is honoured.
  Future<void> _authenticate() async {
    if (mounted) setState(() => _checking = true);
    final AppLockOutcome outcome = await ref
        .read(appLockProvider)
        .authenticate(
          reason: AppLocalizations.of(context).privateLibraryUnlockReason,
        );
    if (mounted) {
      setState(() => _pass(unlocked: outcome == AppLockOutcome.passed));
    }
  }

  void _pass({required bool unlocked}) {
    _unlocked = unlocked;
    _checking = false;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.privateLibraryTitle)),
      body: _body(context, l10n),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    if (_checking) return const Center(child: CircularProgressIndicator());
    if (!_unlocked) return _locked(l10n);
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
      onAction: _authenticate,
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
