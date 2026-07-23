import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';

/// The user-facing name of a [StorageVolumeKind].
///
/// Shared by the Settings volume chooser and the download-time device/card
/// sheet so the two never drift into calling the same disk different things —
/// the volume twin of `storageTierLabel`.
///
/// ```dart
/// storageVolumeLabel(l10n, StorageVolumeKind.sdCard); // 'SD card'
/// ```
String storageVolumeLabel(AppLocalizations l10n, StorageVolumeKind kind) {
  return switch (kind) {
    StorageVolumeKind.device => l10n.settingsStorageVolumeDevice,
    StorageVolumeKind.sdCard => l10n.settingsStorageVolumeSdCard,
  };
}

/// One line explaining which disk a [StorageVolumeKind] stands for.
String storageVolumeDetail(AppLocalizations l10n, StorageVolumeKind kind) {
  return switch (kind) {
    StorageVolumeKind.device => l10n.settingsStorageVolumeDeviceDetail,
    StorageVolumeKind.sdCard => l10n.settingsStorageVolumeSdCardDetail,
  };
}

/// The icon standing for a [StorageVolumeKind] wherever one is offered.
IconData storageVolumeIcon(StorageVolumeKind kind) {
  return switch (kind) {
    StorageVolumeKind.device => Icons.smartphone,
    StorageVolumeKind.sdCard => Icons.sd_card_outlined,
  };
}
