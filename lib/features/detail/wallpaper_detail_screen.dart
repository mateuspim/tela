import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';

/// Full-screen preview and the shortest path to applying a wallpaper.
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

  void _showResult(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  int _previewCacheWidth(BuildContext context) {
    final double physicalWidth =
        MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context);
    return (physicalWidth * 2).round().clamp(
      1,
      widget.wallpaper.resolution.width,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.wallpaper.resolution.toString())),
      body: Column(
        children: <Widget>[
          Expanded(child: _preview(context, l10n)),
          SafeArea(
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
          ),
        ],
      ),
    );
  }

  Widget _preview(BuildContext context, AppLocalizations l10n) {
    return Semantics(
      image: true,
      label: l10n.detailPreviewLabel(widget.wallpaper.id),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return InteractiveViewer(
            maxScale: 4,
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: CachedNetworkImage(
                imageUrl: widget.wallpaper.fullImageUrl,
                fit: BoxFit.contain,
                memCacheWidth: _previewCacheWidth(context),
                placeholder: (_, _) => const Center(
                  child: CircularProgressIndicator(),
                ),
                errorWidget: (_, _, _) => const Center(
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
