import 'package:flutter/material.dart';

/// The small caption a settings section puts above its own control.
///
/// One definition so the accent swatches and the tile-density steps cannot
/// drift into different label weights inside the same Appearance group.
///
/// ```dart
/// SettingsSectionLabel(text: l10n.settingsAccentTitle);
/// ```
class SettingsSectionLabel extends StatelessWidget {
  /// Creates the caption for a settings section.
  const SettingsSectionLabel({required this.text, super.key});

  /// The localized caption.
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
