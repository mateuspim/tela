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
      appBar: AppBar(title: Text(l10n.settingsTitle)),
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
    return ListView(
      children: <Widget>[
        _Header(title: l10n.settingsAccountSection),
        const ApiKeySection(),
        const Divider(),
        _Header(title: l10n.settingsDownloadsSection),
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
        const Divider(),
        _Header(title: l10n.settingsPrivacySection),
        const _PrivateLibraryTile(),
      ],
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

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
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
