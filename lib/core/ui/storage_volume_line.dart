import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/storage_volume_kind_text.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';

/// "Saves to SD card" / "Saves to Internal storage", with the disk's icon.
///
/// Shown under a storage tier wherever one is offered — the download chooser
/// and the Settings pickers — because the tier name alone does not say which
/// disk it is: the private library stays on the device whatever card the
/// files tier points at (owner, 2026-10-16).
///
/// ```dart
/// StorageVolumeLine(kind: location.volumeFor(StorageTier.appPrivate)!);
/// ```
class StorageVolumeLine extends StatelessWidget {
  /// Creates the line for [kind].
  const StorageVolumeLine({required this.kind, super.key});

  /// The disk being named.
  final StorageVolumeKind kind;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextStyle? style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Row(
      spacing: 4,
      children: <Widget>[
        Icon(storageVolumeIcon(kind), size: 14, color: style?.color),
        Flexible(
          child: Text(
            l10n.downloadDestinationVolume(storageVolumeLabel(l10n, kind)),
            style: style,
          ),
        ),
      ],
    );
  }
}
