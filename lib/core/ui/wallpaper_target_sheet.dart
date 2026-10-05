import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/sheet_header.dart';
import 'package:tela/domain/models/wallpaper_target.dart';

/// Asks which Android surface a wallpaper should be applied to.
///
/// Shared by every screen that can apply one — the detail screen and the
/// download history — so "Home, Lock, or Both" reads the same wherever it is
/// offered. Resolves to null when the sheet is dismissed.
///
/// ```dart
/// final WallpaperTarget? target = await chooseWallpaperTarget(context);
/// if (target != null) await applyWallpaper(wallpaper, target);
/// ```
Future<WallpaperTarget?> chooseWallpaperTarget(BuildContext context) {
  return showModalBottomSheet<WallpaperTarget>(
    context: context,
    // Root, so the scrim also dims the shell's rail — from a tab's own
    // navigator it stopped at the rail's edge (device survey, 2026-10-05).
    useRootNavigator: true,
    builder: _targetSheet,
  );
}

Widget _targetSheet(BuildContext context) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  return SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SheetHeader(title: l10n.detailTargetTitle),
        _targetTile(
          context,
          l10n.detailTargetHome,
          Icons.home_outlined,
          WallpaperTarget.home,
        ),
        _targetTile(
          context,
          l10n.detailTargetLock,
          Icons.lock_outline,
          WallpaperTarget.lock,
        ),
        _targetTile(
          context,
          l10n.detailTargetBoth,
          Icons.smartphone_outlined,
          WallpaperTarget.both,
        ),
      ],
    ),
  );
}

Widget _targetTile(
  BuildContext context,
  String label,
  IconData icon,
  WallpaperTarget target,
) {
  return ListTile(
    leading: Icon(icon),
    title: Text(label),
    onTap: () => Navigator.pop(context, target),
  );
}
