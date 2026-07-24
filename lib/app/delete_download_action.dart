import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/domain/models/download_deletion.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/storage_tier.dart';

/// Confirms (unless Android already will), hard-deletes the download, and
/// reports the outcome — the one entry point every "Delete from device" uses.
///
/// Returns whether the file was actually deleted, so a viewer can advance or
/// close and a screen can refresh only when something changed: false covers a
/// cancelled confirmation, a declined system prompt, and a failure alike.
///
/// The gallery tier on Android 30+ carries the OS's own delete confirmation, so
/// tela's is suppressed there to avoid a confirm-on-confirm; every other case —
/// the private and files tiers, and the older API where a gallery delete is
/// silent — keeps tela's dialog, since it is then the only warning there is.
///
/// ```dart
/// final bool gone = await confirmAndDeleteDownload(
///   context: context, ref: ref,
///   id: record.wallpaper.id, tier: record.tier, location: record.location);
/// if (gone) Navigator.of(context).maybePop();
/// ```
Future<bool> confirmAndDeleteDownload({
  required BuildContext context,
  required WidgetRef ref,
  required String id,
  required StorageTier tier,
  required Uri location,
}) async {
  final bool systemConfirms =
      tier == StorageTier.sharedGallery &&
      await ref.read(imageStoreProvider).galleryDeleteConfirmedBySystem();
  if (!context.mounted) return false;
  if (!systemConfirms) {
    final bool confirmed = await _confirmHardDelete(context);
    if (!confirmed || !context.mounted) return false;
  }
  // Read before the delete's async gap: a viewer pops itself on success, so the
  // messenger it reports through must be captured while its context is alive.
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final AppLocalizations l10n = AppLocalizations.of(context);
  return _deleteAndReport(
    ref,
    messenger,
    l10n,
    id: id,
    tier: tier,
    location: location,
  );
}

/// The honest-scope confirmation: unlike "Remove from history", this really
/// does delete the file, and says so.
Future<bool> _confirmHardDelete(BuildContext context) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(l10n.downloadDeleteTitle),
      content: Text(l10n.downloadDeleteBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.downloadDelete),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

Future<bool> _deleteAndReport(
  WidgetRef ref,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n, {
  required String id,
  required StorageTier tier,
  required Uri location,
}) async {
  try {
    final DownloadDeletion outcome = await ref.read(deleteDownloadProvider)(
      id: id,
      tier: tier,
      location: location,
    );
    if (outcome == DownloadDeletion.deleted) {
      showTelaToast(messenger, l10n.downloadDeleteDone);
    }
    return outcome == DownloadDeletion.deleted;
  } on ImageStoreFailure {
    showTelaToast(
      messenger,
      l10n.downloadDeleteFailure,
      kind: ToastKind.failure,
    );
    return false;
  }
}
