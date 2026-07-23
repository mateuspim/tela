import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/sheet_header.dart';
import 'package:tela/core/ui/storage_volume_kind_text.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';

/// Asks which volume a fresh files-outside-gallery download should land on.
///
/// The download-time twin of the Settings chooser: the first time a download
/// routes to the shared-but-hidden tier and no folder is set, this offers the
/// same "Internal storage / SD card" choice rather than dropping the user into a
/// blank system tree browser. The card row appears only when [offerSdCard].
/// Resolves to null when the sheet is dismissed, or when [context] is already
/// gone by the time the download failed and called back.
///
/// ```dart
/// final StorageVolumeKind? kind =
///     await chooseDownloadVolume(context, offerSdCard: true);
/// ```
Future<StorageVolumeKind?> chooseDownloadVolume(
  BuildContext context, {
  required bool offerSdCard,
}) {
  if (!context.mounted) return Future<StorageVolumeKind?>.value();
  return showModalBottomSheet<StorageVolumeKind>(
    context: context,
    builder: (BuildContext context) => _volumeSheet(context, offerSdCard),
  );
}

Widget _volumeSheet(BuildContext context, bool offerSdCard) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  return SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SheetHeader(title: l10n.settingsDownloadLocationTitle),
        _volumeTile(context, l10n, StorageVolumeKind.device),
        if (offerSdCard) _volumeTile(context, l10n, StorageVolumeKind.sdCard),
      ],
    ),
  );
}

Widget _volumeTile(
  BuildContext context,
  AppLocalizations l10n,
  StorageVolumeKind kind,
) {
  return ListTile(
    leading: Icon(storageVolumeIcon(kind)),
    title: Text(storageVolumeLabel(l10n, kind)),
    subtitle: Text(storageVolumeDetail(l10n, kind)),
    onTap: () => Navigator.pop(context, kind),
  );
}
