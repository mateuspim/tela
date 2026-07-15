import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/storage_tier_text.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/features/settings/api_key_section.dart';
import 'package:tela/features/settings/app_lock_switch.dart';
import 'package:tela/features/settings/browse_defaults_section.dart';
import 'package:tela/features/settings/storage_settings_controller.dart';

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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: constraints.maxWidth >= _twoColumnWidth
                    ? _wideGroups(l10n)
                    : _compactGroups(l10n),
              ),
            ),
          ),
    );
  }

  static const double _twoColumnWidth = 900;

  Widget _compactGroups(AppLocalizations l10n) {
    return Column(
      children: <Widget>[
        _accountGroup(l10n),
        const SizedBox(height: 16),
        _browseGroup(l10n),
        const SizedBox(height: 16),
        _downloadsGroup(l10n),
        const SizedBox(height: 16),
        _privacyGroup(l10n),
      ],
    );
  }

  Widget _wideGroups(AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            children: <Widget>[
              _accountGroup(l10n),
              const SizedBox(height: 16),
              _browseGroup(l10n),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: <Widget>[
              _downloadsGroup(l10n),
              const SizedBox(height: 16),
              _privacyGroup(l10n),
            ],
          ),
        ),
      ],
    );
  }

  Widget _accountGroup(AppLocalizations l10n) {
    return _SettingsGroup(
      icon: Icons.key_outlined,
      title: l10n.settingsAccountSection,
      description: l10n.settingsAccountDescription,
      children: const <Widget>[ApiKeySection()],
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
        const _DownloadHistoryTile(),
        const Divider(),
        _TierPicker(
          title: l10n.settingsDownloadsSfw,
          purity: Purity.sfw,
          selected: settings.sfwTier,
        ),
        const Divider(),
        _TierPicker(
          title: l10n.settingsDownloadsNsfw,
          purity: Purity.nsfw,
          selected: settings.nsfwTier,
          note: l10n.settingsDownloadsNsfwNote,
        ),
      ],
    );
  }

  Widget _privacyGroup(AppLocalizations l10n) {
    return _SettingsGroup(
      icon: Icons.shield_outlined,
      title: l10n.settingsPrivacySection,
      description: l10n.settingsPrivacyDescription,
      children: const <Widget>[
        _PrivateLibraryTile(),
        Divider(),
        AppLockSwitch(),
      ],
    );
  }
}

/// The way into the download history.
///
/// It sits above the destination pickers because it is what they produce: the
/// wallpapers already on this device, each one ready to be set again.
class _DownloadHistoryTile extends StatelessWidget {
  const _DownloadHistoryTile();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListTile(
      leading: const Icon(Icons.history_outlined),
      title: Text(l10n.downloadHistoryTitle),
      subtitle: Text(l10n.downloadHistoryOpenDetail),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.pushNamed(TelaRoutes.downloadHistoryName),
    );
  }
}

/// The way into the private library.
///
/// It lives here rather than in the browse app bar on purpose: this is where
/// explicit downloads land, and a heart-shaped shortcut to them on the app's
/// front page is not what anyone wants over a shoulder.
class _PrivateLibraryTile extends StatelessWidget {
  const _PrivateLibraryTile();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListTile(
      leading: const Icon(Icons.lock_outline),
      title: Text(l10n.privateLibraryTitle),
      subtitle: Text(l10n.privateLibraryOpenDetail),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.pushNamed(TelaRoutes.privateLibraryName),
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
        ListTile(title: Text(title), dense: true),
        RadioGroup<StorageTier>(
          groupValue: selected,
          onChanged: (StorageTier? tier) => _route(ref, tier),
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

  void _route(WidgetRef ref, StorageTier? tier) {
    if (tier == null) return;
    unawaited(ref.read(storageSettingsProvider.notifier).route(purity, tier));
  }
}
