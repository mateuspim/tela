import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/domain/models/bitmap_export_rule.dart';
import 'package:tela/domain/models/clipboard_confirmation.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_share_failure.dart';

/// Copies a wallpaper's image to the system clipboard and reports the outcome.
///
/// The one entry point for both ways tela copies — the share sheet's *Copy
/// image* tile and holding the image itself — so the confirmation rule is
/// written once. That rule is the whole reason this is not two lines at each
/// call site: from Android 13 the platform shows its own clipboard preview, so
/// tela's toast fires only below it, and a second copy of that condition is a
/// second chance to get it wrong.
///
/// Callers must have checked [mayExportBitmap] first — an explicit wallpaper's
/// bitmap never leaves, and `ShareWallpaper.clipboard` throws rather than
/// copying it. Both call sites withhold the affordance instead of catching
/// that, so the throw stays what it is: a programming error, not a user one.
///
/// ```dart
/// await copyWallpaperToClipboard(
///   context: context, ref: ref, wallpaper: wallpaper);
/// ```
Future<void> copyWallpaperToClipboard({
  required BuildContext context,
  required WidgetRef ref,
  required Wallpaper wallpaper,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  // Read before the fetch's async gap: a hold can be followed straight out of
  // the surface that started it, and the copy still owes an answer.
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    final ClipboardConfirmation confirmation = await ref
        .read(shareWallpaperProvider)
        .clipboard(wallpaper);
    if (confirmation == ClipboardConfirmation.system) return;
    showTelaToast(messenger, l10n.detailShareClipboardDone);
  } on WallpaperShareFailure {
    showTelaToast(messenger, l10n.detailShareFailure, kind: ToastKind.failure);
  }
}
