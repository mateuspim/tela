import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/core/ui/wallpaper_target_sheet.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';

/// The whole point of the app, as one button: pick home/lock/both, apply.
///
/// It owns its own busy flag rather than taking one, because the spinner is
/// this button's business and nothing else on Detail waits for the apply. It is
/// also the button Wave 1's "≤3 taps" promise is *about* — everything the
/// detail screen does around it (adjust, share, download) is a longer way
/// round, and none of them may tax this one.
///
/// ```dart
/// DetailApplyButton(wallpaper: wallpaper)
/// ```
class DetailApplyButton extends ConsumerStatefulWidget {
  /// Creates the apply button for [wallpaper].
  const DetailApplyButton({required this.wallpaper, super.key});

  /// The wallpaper the button sets.
  final Wallpaper wallpaper;

  @override
  ConsumerState<DetailApplyButton> createState() => _DetailApplyButtonState();
}

class _DetailApplyButtonState extends ConsumerState<DetailApplyButton> {
  bool _isApplying = false;

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

  void _showResult(String message, {ToastKind kind = ToastKind.success}) {
    showTelaToast(ScaffoldMessenger.of(context), message, kind: kind);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
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
}
