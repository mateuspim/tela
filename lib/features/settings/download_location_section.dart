import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/byte_size_text.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/download_location.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';
import 'package:tela/features/settings/download_location_controller.dart';
import 'package:tela/features/settings/nsfw_removable_guard.dart';
import 'package:tela/features/settings/storage_settings_controller.dart';

/// Picks which volume the files-outside-gallery tier writes to: device or card.
///
/// This is the whole reason the tier and the folder are no longer two separate
/// decisions. Selecting "Files, not gallery" now leads here, where "This
/// device" or "SD card" opens the system picker already aimed at that volume —
/// one tap to confirm, instead of hunting a card down in a blank tree browser.
class DownloadLocationSection extends ConsumerWidget {
  /// Creates the device/card location chooser.
  const DownloadLocationSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<DownloadLocation> location = ref.watch(
      downloadLocationProvider,
    );
    final DownloadLocation? value = location.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListTile(title: Text(l10n.settingsDownloadLocationTitle), dense: true),
        if (value != null) ..._choices(context, ref, value),
      ],
    );
  }

  List<Widget> _choices(
    BuildContext context,
    WidgetRef ref,
    DownloadLocation location,
  ) {
    return <Widget>[
      RadioGroup<StorageVolumeKind>(
        groupValue: location.currentKind,
        onChanged: (StorageVolumeKind? kind) =>
            unawaited(_choose(ref, context, kind)),
        child: Column(
          children: <Widget>[
            _tile(context, StorageVolumeKind.device),
            // The card row appears only when a card is in the slot — or when
            // the current folder is on one that has since been ejected, so the
            // user's own choice is not erased from the screen.
            if (location.offersSdCard) _tile(context, StorageVolumeKind.sdCard),
          ],
        ),
      ),
      _status(context, location.folder),
    ];
  }

  Widget _tile(BuildContext context, StorageVolumeKind kind) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isCard = kind == StorageVolumeKind.sdCard;
    return RadioListTile<StorageVolumeKind>(
      value: kind,
      secondary: Icon(isCard ? Icons.sd_card_outlined : Icons.smartphone),
      title: Text(
        isCard
            ? l10n.settingsStorageVolumeSdCard
            : l10n.settingsStorageVolumeDevice,
      ),
      subtitle: Text(
        isCard
            ? l10n.settingsStorageVolumeSdCardDetail
            : l10n.settingsStorageVolumeDeviceDetail,
      ),
    );
  }

  /// The line under the choice: where files land now, or why they can't.
  Widget _status(BuildContext context, DownloadFolder? folder) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool problem = folder != null && !folder.isAvailable;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Text(
        _statusText(l10n, folder),
        style: theme.textTheme.bodySmall?.copyWith(
          color: problem
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  String _statusText(AppLocalizations l10n, DownloadFolder? folder) {
    if (folder == null) return l10n.settingsDownloadFolderNone;
    if (!folder.isAvailable) return l10n.settingsDownloadFolderUnavailable;
    final int? free = folder.freeBytes;
    final String location = _location(folder);
    if (free == null) return location;
    return '$location · ${l10n.settingsDownloadFolderFree(formatBytes(free))}';
  }

  /// Volume first, then the path inside it — the order the picker showed.
  String _location(DownloadFolder folder) {
    if (folder.relativePath.isEmpty) return folder.volumeLabel;
    return '${folder.volumeLabel}/${folder.relativePath}';
  }

  /// Points downloads at [kind]'s volume, then warns if the newly chosen folder
  /// is a removable card that explicit downloads already route to. This is the
  /// second edge of slice 4's warning, and the one easily missed: NSFW can
  /// already sit on files-outside-gallery here, so choosing a card is what tips
  /// it onto removable storage.
  ///
  /// Unlike the tier picker, the grant is already taken by the time the warning
  /// shows, so a decline cannot un-choose the folder — it routes NSFW to the
  /// private tier instead, leaving the card serving safe downloads.
  Future<void> _choose(
    WidgetRef ref,
    BuildContext context,
    StorageVolumeKind? kind,
  ) async {
    if (kind == null) return;
    await ref.read(downloadLocationProvider.notifier).choose(kind);
    if (!context.mounted) return;

    final StorageSettings settings = await ref.read(
      storageSettingsProvider.future,
    );
    final DownloadLocation location = await ref.read(
      downloadLocationProvider.future,
    );
    if (!context.mounted) return;
    final bool proceed = await confirmExplicitOnRemovable(
      ref,
      context,
      nsfwTier: settings.nsfwTier,
      folderRemovable: location.folder?.isRemovable ?? false,
    );
    if (proceed) return;
    await ref
        .read(storageSettingsProvider.notifier)
        .route(Purity.nsfw, StorageTier.appPrivate);
  }
}
