import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/app/storage_settings_controller.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/balanced_columns.dart';
import 'package:tela/core/ui/storage_tier_text.dart';
import 'package:tela/domain/models/download_location.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/features/library/library_destination_tile.dart';
import 'package:tela/features/settings/accent_color_section.dart';
import 'package:tela/features/settings/api_key_section.dart';
import 'package:tela/features/settings/app_lock_switch.dart';
import 'package:tela/features/settings/browse_defaults_section.dart';
import 'package:tela/features/settings/clear_cache_tile.dart';
import 'package:tela/features/settings/download_location_controller.dart';
import 'package:tela/features/settings/download_location_section.dart';
import 'package:tela/features/settings/nsfw_removable_guard.dart';
import 'package:tela/features/settings/pinned_destination_notice.dart';
import 'package:tela/features/settings/settings_section_label.dart';
import 'package:tela/features/settings/tile_density_section.dart';

/// Where downloads go, configured for safe and explicit content separately.
class SettingsScreen extends ConsumerWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<StorageSettings> settings = ref.watch(
      storageSettingsProvider,
    );
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Text(
          l10n.settingsTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      body: settings.when(
        data: (StorageSettings value) => _SettingsList(settings: value),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) =>
            Center(child: Text(l10n.errorUnexpected)),
      ),
    );
  }
}

/// Every settings group, in screen order.
class _SettingsList extends StatelessWidget {
  const _SettingsList({required this.settings});

  final StorageSettings settings;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) =>
          SingleChildScrollView(
            // Under edge-to-edge the body draws behind the bottom system bar,
            // so add its inset to the fixed 32: the last group has to be able
            // to scroll clear of a gesture bar or nav bar, not strand behind
            // it. Same live-inset approach as `wallpaperGridPadding`. (A
            // floating OEM taskbar overlay is not reported as an inset — that
            // one the user dismisses; see device check 2026-07-21.)
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              32 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: BalancedColumns(
                  columnCount: constraints.maxWidth >= _twoColumnWidth ? 2 : 1,
                  spacing: 16,
                  children: _groups(l10n),
                ),
              ),
            ),
          ),
    );
  }

  static const double _twoColumnWidth = 900;

  /// The groups in reading order.
  ///
  /// One list for both layouts: [BalancedColumns] measures and distributes, so
  /// there is no second hand-assigned order to keep in step with this one.
  List<Widget> _groups(AppLocalizations l10n) {
    return <Widget>[
      _accountGroup(l10n),
      _appearanceGroup(l10n),
      _browseGroup(l10n),
      _downloadsGroup(l10n),
      _storageGroup(l10n),
      _privacyGroup(l10n),
    ];
  }

  Widget _accountGroup(AppLocalizations l10n) {
    return _SettingsGroup(
      icon: Icons.key_outlined,
      title: l10n.settingsAccountSection,
      description: l10n.settingsAccountDescription,
      children: const <Widget>[ApiKeySection()],
    );
  }

  Widget _appearanceGroup(AppLocalizations l10n) {
    return _SettingsGroup(
      icon: Icons.palette_outlined,
      title: l10n.settingsAppearanceSection,
      description: l10n.settingsAppearanceDescription,
      children: const <Widget>[AccentColorSection(), TileDensitySection()],
    );
  }

  Widget _browseGroup(AppLocalizations l10n) {
    return _SettingsGroup(
      icon: Icons.tune,
      title: l10n.settingsBrowseDefaultsSection,
      description: l10n.settingsBrowseDefaultsDescription,
      children: const <Widget>[
        BrowseDefaultsSection(),
        Divider(),
        _BlockedTagsTile(),
      ],
    );
  }

  Widget _downloadsGroup(AppLocalizations l10n) {
    return _SettingsGroup(
      icon: Icons.download_outlined,
      title: l10n.settingsDownloadsSection,
      description: l10n.settingsDownloadsDescription,
      children: <Widget>[
        // Above the destination pickers because it is what they produce: the
        // wallpapers already on this device, each ready to be set again. Also
        // reachable straight from the Library tab now.
        LibraryDestinationTile(
          icon: Icons.history_outlined,
          title: l10n.downloadHistoryTitle,
          subtitle: l10n.downloadHistoryOpenDetail,
          routeName: TelaRoutes.downloadHistoryName,
        ),
        const Divider(),
        // Above the pickers, because while a pin is on those pickers do not
        // decide anything: the pin overrides them for every download.
        const PinnedDestinationNotice(),
        // No dividers between the two pickers and the volume panel: the
        // captions carry the breaks, the way the Appearance card separates its
        // accent and size controls. A slab per sub-decision was what made the
        // block read as rows bolted on in sequence.
        _TierPicker(
          title: l10n.settingsDownloadsSfw,
          purity: Purity.sfw,
          selected: settings.sfwTier,
        ),
        _TierPicker(
          title: l10n.settingsDownloadsNsfw,
          purity: Purity.nsfw,
          selected: settings.nsfwTier,
          note: l10n.settingsDownloadsNsfwNote,
        ),
        // Only when a purity actually routes there, and under both pickers
        // rather than inside either: one folder serves the tier whichever
        // purity uses it, so a copy per picker would suggest there are two.
        // Its own inset panel says it is a detail of the Files destination, not
        // a third peer decision.
        if (_usesFilesOutsideGallery) const DownloadLocationSection(),
      ],
    );
  }

  /// Whether either purity sends downloads to the files-outside-gallery tier.
  ///
  /// The device/card choice is meaningless until something routes there, so it
  /// stays hidden rather than sitting as a dead control under the gallery and
  /// private-library defaults.
  bool get _usesFilesOutsideGallery =>
      settings.sfwTier == StorageTier.filesOutsideGallery ||
      settings.nsfwTier == StorageTier.filesOutsideGallery;

  /// Its own group rather than a line under Downloads, because the difference
  /// between the two is the whole point: a download is a file the user kept,
  /// and everything in the cache is a copy tela can fetch again.
  Widget _storageGroup(AppLocalizations l10n) {
    return _SettingsGroup(
      icon: Icons.sd_storage_outlined,
      title: l10n.settingsStorageSection,
      description: l10n.settingsStorageDescription,
      children: const <Widget>[ClearCacheTile()],
    );
  }

  Widget _privacyGroup(AppLocalizations l10n) {
    return _SettingsGroup(
      icon: Icons.shield_outlined,
      title: l10n.settingsPrivacySection,
      description: l10n.settingsPrivacyDescription,
      children: <Widget>[
        // Here beside the app-lock as well as on the Library tab: this is where
        // explicit downloads land, and both entries stay a plain locked row
        // rather than a thumbnailed shortcut over a shoulder.
        LibraryDestinationTile(
          icon: Icons.lock_outline,
          title: l10n.privateLibraryTitle,
          subtitle: l10n.privateLibraryOpenDetail,
          routeName: TelaRoutes.privateLibraryName,
        ),
        const Divider(),
        const AppLockSwitch(),
      ],
    );
  }
}

/// The way into the tags blocked from every search.
class _BlockedTagsTile extends StatelessWidget {
  const _BlockedTagsTile();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListTile(
      leading: const Icon(Icons.label_off_outlined),
      title: Text(l10n.blockedTagsTitle),
      subtitle: Text(l10n.blockedTagsOpenDetail),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.pushNamed(TelaRoutes.blockedTagsName),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.icon,
    required this.title,
    required this.description,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: <Widget>[
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          ...children,
        ],
      ),
    );
  }
}

/// The tiers a [Purity] may be routed to, as a single-choice list.
///
/// The options come from the domain, so the gallery is absent for NSFW because
/// the rule says so — not because this widget remembered to hide it.
class _TierPicker extends ConsumerWidget {
  const _TierPicker({
    required this.title,
    required this.purity,
    required this.selected,
    this.note,
  });

  final String title;
  final Purity purity;
  final StorageTier selected;
  final String? note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                _tile(context, tier),
            ],
          ),
        ),
        if (note != null) _note(context, note!),
      ],
    );
  }

  Widget _tile(BuildContext context, StorageTier tier) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return RadioListTile<StorageTier>(
      value: tier,
      secondary: Icon(storageTierIcon(tier)),
      title: Text(storageTierLabel(l10n, tier)),
      subtitle: Text(storageTierDetail(l10n, tier)),
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
        folderRemovable: location.folder?.isRemovable ?? false,
      );
      // Declined: leave NSFW on its current (private) tier — nothing written.
      if (!proceed) return;
    }
    await ref.read(storageSettingsProvider.notifier).route(purity, tier);
  }
}
