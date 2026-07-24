import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_failure_text.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/use_cases/save_api_key.dart';
import 'package:tela/features/settings/api_key_controller.dart';
import 'package:tela/features/settings/api_key_dialog.dart';

/// The Wallhaven API key row: whether one is stored, and how to change that.
///
/// It renders the key's *presence*, never the key. Once saved, a key can be
/// replaced or removed but not read back out of the app.
class ApiKeySection extends ConsumerWidget {
  /// Creates the API-key section of the settings screen.
  const ApiKeySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool stored = ref.watch(apiKeyProvider).value ?? false;

    return ListTile(
      leading: const Icon(Icons.key_outlined),
      title: Text(l10n.settingsApiKeyTitle),
      subtitle: Text(
        stored ? l10n.settingsApiKeyPresent : l10n.settingsApiKeyAbsent,
      ),
      trailing: stored ? _removeButton(context, ref, l10n) : null,
      onTap: () => _enterKey(context, ref),
    );
  }

  Widget _removeButton(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    return IconButton(
      icon: const Icon(Icons.delete_outline),
      tooltip: l10n.settingsApiKeyRemove,
      onPressed: () => _forgetKey(context, ref),
    );
  }

  Future<void> _enterKey(BuildContext context, WidgetRef ref) async {
    final String? key = await showApiKeyDialog(context);
    if (key == null || !context.mounted) return;
    await _save(context, ref, key);
  }

  Future<void> _save(BuildContext context, WidgetRef ref, String key) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final ApiKeySaveOutcome outcome = await ref
          .read(apiKeyProvider.notifier)
          .save(key);
      messenger.showSnackBar(SnackBar(content: Text(_saved(l10n, outcome))));
    } on SourceFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text(localizedFailure(l10n, failure))),
      );
    }
  }

  String _saved(AppLocalizations l10n, ApiKeySaveOutcome outcome) {
    return switch (outcome) {
      ApiKeySaveOutcome.verified => l10n.settingsApiKeySaved,
      ApiKeySaveOutcome.savedUnverified => l10n.settingsApiKeyUnverified,
    };
  }

  Future<void> _forgetKey(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await ref.read(apiKeyProvider.notifier).forget();
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.settingsApiKeyRemoved)),
    );
  }
}
