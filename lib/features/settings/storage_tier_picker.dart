import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/storage_settings_controller.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/storage_tier_text.dart';
import 'package:tela/core/ui/storage_volume_line.dart';
import 'package:tela/domain/models/download_location.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';
import 'package:tela/features/settings/download_location_controller.dart';
import 'package:tela/features/settings/download_location_section.dart';
import 'package:tela/features/settings/nsfw_removable_guard.dart';
import 'package:tela/features/settings/settings_section_label.dart';

/// The tiers a [Purity] may be routed to, as a single-choice list.
///
/// The options come from the domain, so the gallery is absent for NSFW because
/// the rule says so — not because this widget remembered to hide it.
class StorageTierPicker extends ConsumerWidget {
  /// Creates the picker for [purity], with [selected] checked.
  const StorageTierPicker({
    required this.title,
    required this.purity,
    required this.selected,
    this.note,
    super.key,
  });

  /// The caption above the options.
  final String title;

  /// The purity bucket this picker routes.
  final Purity purity;

  /// The tier currently configured for [purity].
  final StorageTier selected;

  /// An optional line under the options.
  final String? note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DownloadLocation? location = ref
        .watch(downloadLocationProvider)
        .value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SettingsSectionLabel(text: title),
        ),
        RadioGroup<StorageTier>(
          groupValue: selected,
          onChanged: (StorageTier? tier) =>
              unawaited(_route(ref, context, tier)),
          child: Column(
            children: <Widget>[
              for (final StorageTier tier in StorageSettings.choicesFor(purity))
                _tile(context, tier, location?.volumeFor(tier, purity)),
            ],
          ),
        ),
        // Right under the choice it belongs to, and only while that choice is
        // "Files, not gallery": each purity has its own folder now, and a
        // folder panel for a tier nothing routes to is a control for nothing.
        if (selected == StorageTier.filesOutsideGallery)
          DownloadLocationSection(purity: purity),
        if (note != null) _note(context, note!),
        if (_privateStaysNoteDue(location))
          _note(context, AppLocalizations.of(context).settingsPrivateOnDevice),
      ],
    );
  }

  /// Whether to say outright that the private library ignores the card.
  ///
  /// Only on the explicit picker and only with a card in play: that is where
  /// "Private library" read as "my private stuff, on the card I set up"
  /// (owner, 2026-10-16). Without a card there is no other disk to confuse.
  bool _privateStaysNoteDue(DownloadLocation? location) {
    return purity == Purity.nsfw && (location?.offersSdCard ?? false);
  }

  Widget _tile(
    BuildContext context,
    StorageTier tier,
    StorageVolumeKind? kind,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return RadioListTile<StorageTier>(
      value: tier,
      secondary: Icon(storageTierIcon(tier)),
      title: Text(storageTierLabel(l10n, tier)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: <Widget>[
          Text(storageTierDetail(l10n, tier)),
          if (kind != null) StorageVolumeLine(kind: kind),
        ],
      ),
    );
  }

  Widget _note(BuildContext context, String text) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// Routes [purity] to [tier], warning *before* it lands when this is the NSFW
  /// picker moving to files-outside-gallery and the folder is a removable card.
  /// This edge and the folder chooser's are the two moments explicit downloads
  /// can first point at a card; gating before the write means a declined
  /// warning never persists the unsafe routing, even for the frame it is open.
  Future<void> _route(
    WidgetRef ref,
    BuildContext context,
    StorageTier? tier,
  ) async {
    if (tier == null) return;
    if (purity == Purity.nsfw && tier == StorageTier.filesOutsideGallery) {
      final DownloadLocation location = await ref.read(
        downloadLocationProvider.future,
      );
      if (!context.mounted) return;
      final bool proceed = await confirmExplicitOnRemovable(
        ref,
        context,
        nsfwTier: tier,
        folderRemovable: location.explicitFolder?.isRemovable ?? false,
      );
      // Declined: leave NSFW on its current (private) tier — nothing written.
      if (!proceed) return;
    }
    await ref.read(storageSettingsProvider.notifier).route(purity, tier);
  }
}
