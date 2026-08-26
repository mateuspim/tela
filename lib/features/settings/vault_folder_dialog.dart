import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/vault_folder.dart';

/// Asks for a new hidden-folder name, resolving to null when nothing changed.
///
/// Validates as the user types rather than on submit: the rule ("no dot, no
/// separator") is not one anybody should have to discover by being refused, and
/// the field can say so while the word is still being written.
///
/// ```dart
/// final VaultFolder? chosen = await askVaultFolder(context, current);
/// ```
Future<VaultFolder?> askVaultFolder(
  BuildContext context,
  VaultFolder current,
) {
  return showDialog<VaultFolder>(
    context: context,
    builder: (BuildContext context) => _VaultFolderDialog(current: current),
  );
}

class _VaultFolderDialog extends StatefulWidget {
  const _VaultFolderDialog({required this.current});

  final VaultFolder current;

  @override
  State<_VaultFolderDialog> createState() => _VaultFolderDialogState();
}

class _VaultFolderDialogState extends State<_VaultFolderDialog> {
  late final TextEditingController _field = TextEditingController(
    text: widget.current.label,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  /// The vault the current text names, or null while it names none.
  ///
  /// [VaultFolder.sanitize] rather than the constructor: the field holds
  /// whatever was typed, and a half-written name is an ordinary state of a text
  /// box rather than an error to throw over.
  VaultFolder? get _typed => VaultFolder.sanitize(_field.text);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.settingsVaultEditTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _input(l10n),
            const SizedBox(height: 16),
            _note(l10n.settingsVaultEditNote),
            const SizedBox(height: 12),
            _note(l10n.settingsVaultEditWarning),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: const Key('vault-folder-save'),
          onPressed: _typed == null
              ? null
              : () => Navigator.pop(context, _typed),
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }

  Widget _input(AppLocalizations l10n) {
    final VaultFolder? typed = _typed;
    return TextField(
      key: const Key('vault-folder-field'),
      controller: _field,
      autofocus: true,
      maxLength: 32,
      decoration: InputDecoration(
        // The leading dot is the app's, not the user's, so it is shown as a
        // fixed prefix rather than sitting in the editable text where it could
        // be deleted or typed twice.
        prefixText: '.',
        labelText: l10n.settingsVaultTitle,
        helperText: l10n.settingsVaultEditHelp,
        helperMaxLines: 3,
        errorText: _field.text.isEmpty || typed != null
            ? null
            : l10n.settingsVaultInvalid,
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _note(String text) {
    final ThemeData theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
