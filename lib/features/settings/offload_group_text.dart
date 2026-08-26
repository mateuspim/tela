import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/offload_group.dart';

/// The user-facing name of an [OffloadKind].
///
/// Beside its detail line rather than on the enum: `domain` may not import
/// Flutter, and l10n lookup is Flutter — the split `storageTierLabel` makes.
///
/// ```dart
/// offloadGroupLabel(l10n, OffloadKind.galleryDownloads); // 'In your gallery'
/// ```
String offloadGroupLabel(AppLocalizations l10n, OffloadKind kind) {
  return switch (kind) {
    OffloadKind.galleryDownloads => l10n.offloadGroupGallery,
    OffloadKind.deviceFiles => l10n.offloadGroupFiles,
    OffloadKind.privateLibrary => l10n.offloadGroupPrivate,
  };
}

/// What moving [kind] changes besides the disk, with [count] files in it.
///
/// Each group's sentence is written for that group, because the three promise
/// genuinely different things: the gallery one leaves Photos, the files one
/// changes nothing else at all, and the private one leaves the app-lock and
/// every tela screen. One generic line over all three would have to be vague
/// about the half that matters.
String offloadGroupDetail(
  AppLocalizations l10n,
  OffloadKind kind,
  int count,
) {
  return switch (kind) {
    OffloadKind.galleryDownloads => l10n.offloadGroupGalleryDetail(count),
    OffloadKind.deviceFiles => l10n.offloadGroupFilesDetail(count),
    OffloadKind.privateLibrary => l10n.offloadGroupPrivateDetail(count),
  };
}
