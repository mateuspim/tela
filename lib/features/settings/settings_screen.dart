import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/build_edition.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/app/storage_settings_controller.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/balanced_columns.dart';
import 'package:tela/core/ui/band_fade_edge.dart';
import 'package:tela/core/ui/gradient_app_bar.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/features/library/library_destination_tile.dart';
import 'package:tela/features/settings/accent_color_section.dart';
import 'package:tela/features/settings/api_key_section.dart';
import 'package:tela/features/settings/app_lock_switch.dart';
import 'package:tela/features/settings/beam_explicit_switch.dart';
import 'package:tela/features/settings/broken_images_tile.dart';
import 'package:tela/features/settings/browse_defaults_section.dart';
import 'package:tela/features/settings/clear_cache_tile.dart';
import 'package:tela/features/settings/collections_section.dart';
import 'package:tela/features/settings/notifications_tile.dart';
import 'package:tela/features/settings/pinned_destination_notice.dart';
import 'package:tela/features/settings/rotation_section.dart';
import 'package:tela/features/settings/storage_tier_picker.dart';
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
      appBar: GradientAppBar(
        toolbarHeight: 72,
        title: Text(
          l10n.settingsTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      body: BandFadeEdge(
        child: settings.when(
          data: (StorageSettings value) => _SettingsList(
            settings: value,
            edition: ref.watch(buildEditionProvider),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace stackTrace) =>
              Center(child: Text(l10n.errorUnexpected)),
        ),
      ),
    );
  }
}

/// Every settings group, in screen order.
class _SettingsList extends StatelessWidget {
  const _SettingsList({required this.settings, required this.edition});

  final StorageSettings settings;

  /// For copy only; the key section itself stays on the `buildEdition` const
  /// so a clean release compiles it out.
  final BuildEdition edition;

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
              // 12, not 8: the band's fade covers the top 12 (BandFadeEdge),
              // and a page at rest should sit clear of it.
              12,
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
      _wallpaperGroup(l10n),
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
      // Without credentials there is no key to connect and no explicit content
      // to unlock; promising both was device pass F6 (2026-10-03).
      description: edition.allowsWallhavenCredentials
          ? l10n.settingsAccountDescription
          : l10n.settingsAccountDescriptionNoKey,
      children: <Widget>[
        if (buildEdition.allowsWallhavenCredentials) const ApiKeySection(),
        const CollectionsSection(),
      ],
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

  /// The device wallpaper itself — distinct from Appearance, which is about
  /// how tela looks rather than what it puts on the screen.
  Widget _wallpaperGroup(AppLocalizations l10n) {
    return _SettingsGroup(
      icon: Icons.wallpaper_outlined,
      title: l10n.settingsWallpaperSection,
      description: l10n.settingsWallpaperDescription,
      children: const <Widget>[RotationSection()],
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
        // Beside the work it announces, rather than under Storage: the queue
        // and the offload both run behind this notification, and with it off
        // they run with nothing on screen to say they exist.
        const NotificationsTile(),
        const Divider(),
        // Above the pickers, because while a pin is on those pickers do not
        // decide anything: the pin overrides them for every download.
        const PinnedDestinationNotice(),
        // No dividers between the two pickers and the volume panel: the
        // captions carry the breaks, the way the Appearance card separates its
        // accent and size controls. A slab per sub-decision was what made the
        // block read as rows bolted on in sequence.
        StorageTierPicker(
          title: l10n.settingsDownloadsSfw,
          purity: Purity.sfw,
          selected: settings.sfwTier,
        ),
        if (buildEdition.allowsExplicitContent)
          StorageTierPicker(
            title: l10n.settingsDownloadsNsfw,
            purity: Purity.nsfw,
            selected: settings.nsfwTier,
            note: l10n.settingsDownloadsNsfwNote,
          ),
      ],
    );
  }

  /// Its own group rather than a line under Downloads, because the difference
  /// between the two is the whole point: a download is a file the user kept,
  /// and everything in the cache is a copy tela can fetch again.
  Widget _storageGroup(AppLocalizations l10n) {
    return _SettingsGroup(
      icon: Icons.sd_storage_outlined,
      title: l10n.settingsStorageSection,
      description: l10n.settingsStorageDescription,
      children: const <Widget>[
        ClearCacheTile(),
        Divider(),
        // Under the cache row on purpose: emptying the cache is the free way to
        // get space back, and someone who came here for room should be offered
        // the one that costs nothing before the one that moves their library.
        _OffloadTile(),
        Divider(),
        // Beside the offload because that is where the damage came from: an
        // offload before copies were verified left empty files on the card
        // (owner, 2026-10-07).
        BrokenImagesTile(),
      ],
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
        // Beside the app-lock deliberately: both govern what may leave the
        // private library, and someone weighing one wants to see the other.
        // Edition-gated where the group is not: without explicit purity there
        // is nothing for it to release.
        if (buildEdition.allowsExplicitContent) const BeamExplicitSwitch(),
      ],
    );
  }
}

/// The way into the screen that moves downloads onto an SD card.
class _OffloadTile extends StatelessWidget {
  const _OffloadTile();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListTile(
      key: const Key('settings-offload'),
      leading: const Icon(Icons.drive_file_move_outlined),
      title: Text(l10n.offloadTitle),
      subtitle: Text(l10n.offloadOpenDetail),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.pushNamed(TelaRoutes.offloadName),
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
