import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/storage_settings_controller.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/byte_size_text.dart';
import 'package:tela/core/ui/download_volume_sheet.dart';
import 'package:tela/core/ui/storage_volume_kind_text.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/download_location.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';
import 'package:tela/features/settings/download_location_controller.dart';
import 'package:tela/features/settings/nsfw_removable_guard.dart';
import 'package:tela/features/settings/settings_section_label.dart';
import 'package:tela/features/settings/vault_folder_section.dart';

/// Picks which volume one purity's files-outside-gallery folder is on: device
/// or card.
///
/// This is the whole reason the tier and the folder are no longer two separate
/// decisions. Selecting "Files, not gallery" now leads here, where "This
/// device" or "SD card" opens the system picker already aimed at that volume —
/// one tap to confirm, instead of hunting a card down in a blank tree browser.
///
/// **One per purity bucket**, shown under that bucket's picker and only while
/// it is set to "Files, not gallery": safe and explicit downloads each have
/// their own folder, so explicit ones can sit on the card while safe ones stay
/// on the device (owner, 2026-10-16). The parent decides when to show it; with
/// no folder yet it offers a button to choose one rather than waiting for the
/// first download to ask.
///
/// ```dart
/// const DownloadLocationSection(purity: Purity.nsfw);
/// ```
class DownloadLocationSection extends ConsumerWidget {
  /// Creates the device/card location chooser for [purity]'s folder.
  const DownloadLocationSection({required this.purity, super.key});

  /// Whose folder this is — [Purity.sfw] stands for safe and sketchy.
  final Purity purity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<DownloadLocation> location = ref.watch(
      downloadLocationProvider,
    );
    final DownloadLocation? value = location.value;
    // An inset, tinted panel rather than another full-width slab: the volume
    // is a detail of whichever tier routes to files-outside-gallery, and the
    // recessed surface says so at a glance. The connective line spells it out.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      // A Material, not a coloured Container: the nested RadioListTiles paint
      // their ink on the nearest Material ancestor, so a bare DecoratedBox over
      // them would swallow the splash (and trips a framework assertion in
      // test).
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        // A hairline edge as well as the fill: on a dark card the tint alone is
        // too close to the surface to read as a separate, nested panel.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SettingsSectionLabel(text: _title(l10n)),
                ],
              ),
            ),
            if (value != null) ..._body(context, ref, value),
          ],
        ),
      ),
    );
  }

  String _title(AppLocalizations l10n) {
    if (_explicit) return l10n.settingsExplicitFolderTitle;
    return l10n.settingsSafeFolderTitle;
  }

  bool get _explicit => StorageSettings.bucketFor(purity) == Purity.nsfw;

  /// The volume choice once a folder exists; before that, a button to pick one.
  List<Widget> _body(
    BuildContext context,
    WidgetRef ref,
    DownloadLocation location,
  ) {
    final DownloadFolder? folder = location.folderFor(purity);
    if (folder == null) return <Widget>[_chooseButton(context, ref, location)];
    return _choices(context, ref, location, folder);
  }

  /// "Choose where to store these": the device/card sheet, then the picker.
  Widget _chooseButton(
    BuildContext context,
    WidgetRef ref,
    DownloadLocation location,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: <Widget>[
          _status(context, null),
          FilledButton.tonalIcon(
            onPressed: () => unawaited(_chooseFirst(ref, context, location)),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: Text(l10n.settingsDownloadFolderChoose),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseFirst(
    WidgetRef ref,
    BuildContext context,
    DownloadLocation location,
  ) async {
    final StorageVolumeKind? kind = await chooseDownloadVolume(
      context,
      offerSdCard: location.offersSdCard,
    );
    if (!context.mounted) return;
    await _choose(ref, context, kind);
  }

  List<Widget> _choices(
    BuildContext context,
    WidgetRef ref,
    DownloadLocation location,
    DownloadFolder folder,
  ) {
    return <Widget>[
      RadioGroup<StorageVolumeKind>(
        groupValue: folder.kind,
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
      _status(context, folder),
      // Only in the explicit folder's panel, which only shows while explicit
      // downloads route here. Anywhere else the vault is a folder nothing
      // writes to, and a settings row for it would be a dead control
      // describing a directory that does not exist.
      if (_explicit) ...<Widget>[
        const Divider(height: 1),
        const VaultFolderSection(),
      ],
    ];
  }

  Widget _tile(BuildContext context, StorageVolumeKind kind) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return RadioListTile<StorageVolumeKind>(
      value: kind,
      secondary: Icon(storageVolumeIcon(kind)),
      title: Text(storageVolumeLabel(l10n, kind)),
      subtitle: Text(storageVolumeDetail(l10n, kind)),
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

  /// Points [purity]'s downloads at [kind]'s volume, then — for the explicit
  /// folder — warns if it is now a removable card. This is the second edge of
  /// slice 4's warning, and the one easily missed: NSFW can already sit on
  /// files-outside-gallery here, so choosing a card is what tips it onto
  /// removable storage. The safe folder has nothing to warn about.
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
    await ref
        .read(downloadLocationProvider.notifier)
        .choose(kind, purity: purity);
    if (!context.mounted || !_explicit) return;

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
      folderRemovable: location.explicitFolder?.isRemovable ?? false,
    );
    if (proceed) return;
    await ref
        .read(storageSettingsProvider.notifier)
        .route(Purity.nsfw, StorageTier.appPrivate);
  }
}
