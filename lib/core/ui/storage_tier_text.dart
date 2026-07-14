import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/storage_tier.dart';

/// The user-facing name of a [StorageTier].
///
/// Shared by the download override sheet and the settings screen so the two
/// never drift into calling the same destination different things.
///
/// ```dart
/// storageTierLabel(l10n, StorageTier.appPrivate); // 'Private library'
/// ```
String storageTierLabel(AppLocalizations l10n, StorageTier tier) {
  return switch (tier) {
    StorageTier.sharedGallery => l10n.storageSharedGallery,
    StorageTier.filesOutsideGallery => l10n.storageFilesOutsideGallery,
    StorageTier.appPrivate => l10n.storageAppPrivate,
  };
}

/// One line explaining what a [StorageTier] means for the files it holds.
String storageTierDetail(AppLocalizations l10n, StorageTier tier) {
  return switch (tier) {
    StorageTier.sharedGallery => l10n.storageSharedGalleryDetail,
    StorageTier.filesOutsideGallery => l10n.storageFilesOutsideGalleryDetail,
    StorageTier.appPrivate => l10n.storageAppPrivateDetail,
  };
}

/// The icon standing for a [StorageTier] wherever one is offered.
IconData storageTierIcon(StorageTier tier) {
  return switch (tier) {
    StorageTier.sharedGallery => Icons.photo_library_outlined,
    StorageTier.filesOutsideGallery => Icons.folder_outlined,
    StorageTier.appPrivate => Icons.lock_outline,
  };
}
