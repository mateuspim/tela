import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';

/// Asks for a Wallhaven API key. Returns what was typed, or null if cancelled.
///
/// Entry is obscured: a key is a password, and this dialog opens in the open,
/// often over someone's shoulder. The result is handed straight to `SaveApiKey`
/// and never kept in widget state.
///
/// ```dart
/// final String? key = await showApiKeyDialog(context);
/// ```
Future<String?> showApiKeyDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => const _ApiKeyDialog(),
  );
}

class _ApiKeyDialog extends StatefulWidget {
  const _ApiKeyDialog();

  @override
  State<_ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<_ApiKeyDialog> {
  final TextEditingController _entry = TextEditingController();

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.settingsApiKeyTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _field(l10n),
          const SizedBox(height: 12),
          Text(l10n.settingsApiKeyHelp, style: _helpStyle(context)),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        _saveButton(l10n),
      ],
    );
  }

  Widget _field(AppLocalizations l10n) {
    return TextField(
      controller: _entry,
      autofocus: true,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(labelText: l10n.settingsApiKeyLabel),
      onChanged: (String _) => setState(() {}),
      onSubmitted: (String _) => _submit(),
    );
  }

  /// Disabled until something is typed, so a blank save can't reach the use
  /// case's ArgumentError as a crash the user caused by tapping a live button.
  Widget _saveButton(AppLocalizations l10n) {
    return FilledButton(
      onPressed: _entry.text.trim().isEmpty ? null : _submit,
      child: Text(l10n.actionSave),
    );
  }

  TextStyle? _helpStyle(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
  }

  void _submit() {
    if (_entry.text.trim().isEmpty) return;
    Navigator.of(context).pop(_entry.text);
  }
}
