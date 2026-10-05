import 'package:flutter/material.dart';

/// The caption that names a bottom sheet, above its list of choices.
///
/// One definition so every chooser sheet — the wallpaper target, the share
/// options, the download volume, the per-download tier — titles itself the same
/// way, and so the title stops borrowing a `ListTile`'s `bodyLarge` weight,
/// which made it read as a disabled first option rather than a heading. The
/// muted `titleSmall` treatment is the sheet twin of the settings sections'
/// `SettingsSectionLabel`; `core/ui` cannot import that feature widget, so the
/// idiom is repeated here rather than shared across the layer boundary.
///
/// ```dart
/// SheetHeader(title: l10n.detailShareTitle);
/// ```
class SheetHeader extends StatelessWidget {
  /// Creates the caption for a chooser sheet.
  const SheetHeader({required this.title, super.key});

  /// The localized sheet title.
  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Left inset matches a ListTile's own content padding, so the caption's
    // edge lines up with the option rows beneath it. Aligned here rather than
    // trusted to the parent: every sheet's Column centres its children by
    // default, which shrink-wrapped the caption into the middle of the sheet
    // (device survey, 2026-10-05).
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
