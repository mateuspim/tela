import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';

/// Warns, once, that explicit downloads on a removable card lose the private
/// tier's protections. Returns `true` to keep saving to the card, `false` to
/// send them to the private library instead.
///
/// There is no dismiss-to-nothing: both actions leave a defined state, because
/// the folder is already granted by the time this opens and "do nothing" would
/// leave explicit files pointed at a card the user never confirmed. Barrier and
/// back both resolve to the safe decline.
///
/// ```dart
/// final bool useCard = await showNsfwRemovableWarning(context);
/// ```
Future<bool> showNsfwRemovableWarning(BuildContext context) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final bool? useCard = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(l10n.settingsNsfwRemovableWarningTitle),
      content: Text(l10n.settingsNsfwRemovableWarningBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.settingsNsfwRemovableWarningDecline),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.settingsNsfwRemovableWarningConfirm),
        ),
      ],
    ),
  );
  // A dismissed dialog (barrier tap, back gesture) is the cautious choice: keep
  // explicit files off the removable card.
  return useCard ?? false;
}
