import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/domain/models/download_location.dart';
import 'package:tela/domain/models/vault_folder.dart';
import 'package:tela/features/settings/download_location_controller.dart';
import 'package:tela/features/settings/vault_folder_dialog.dart';

/// Names the hidden folder explicit downloads land in, and opens the rename.
///
/// In the Privacy group rather than under the download destinations, even
/// though it is a property of the files tier: what it answers is "who else can
/// see this", which is the question that group exists for and the one the
/// app-lock beside it answers differently.
class VaultFolderSection extends ConsumerWidget {
  /// Creates the vault row.
  const VaultFolderSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DownloadLocation? location = ref
        .watch(downloadLocationProvider)
        .value;
    final VaultFolder vault = location?.vault ?? VaultFolder.standard;
    return ListTile(
      key: const Key('settings-vault-folder'),
      leading: const Icon(Icons.folder_off_outlined),
      title: Text(l10n.settingsVaultTitle),
      subtitle: Text(l10n.settingsVaultDetail(vault.directoryName)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(_rename(context, ref, vault)),
    );
  }

  /// Asks for a new label and stores it, reporting only a real failure.
  ///
  /// A dismissed dialog and an unchanged name are both silent: neither is
  /// something the user needs told about a setting they just looked at.
  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    VaultFolder current,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String failure = AppLocalizations.of(context).settingsVaultSaveFailed;
    final VaultFolder? chosen = await askVaultFolder(context, current);
    if (chosen == null || chosen == current) return;
    final bool saved = await ref
        .read(downloadLocationProvider.notifier)
        .renameVault(chosen);
    if (saved) return;
    showTelaToast(messenger, failure, kind: ToastKind.failure);
  }
}
