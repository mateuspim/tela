import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/purity_alert_tint.dart';
import 'package:tela/core/ui/storage_tier_text.dart';
import 'package:tela/core/ui/wallpaper_taxonomy_text.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';

/// Asks where this one download should land; null when dismissed.
///
/// Centred, not a bottom sheet — which is what it replaces. The three
/// destinations differ in *consequence*, not in name (one is indexed into
/// Photos, one is reachable over USB, one is visible to nothing but tela), so
/// this is a decision to be read rather than a menu to be flicked at. A sheet
/// put it at the far edge of a tablet in rows sized for scanning.
///
/// The option list comes from [StorageSettings.choicesFor] rather than being
/// spelled out here: that is where the NSFW invariant lives, and it is why an
/// explicit wallpaper is never offered the gallery.
///
/// ```dart
/// final StorageTier? tier =
///     await chooseDownloadDestination(context, wallpaper.purity);
/// ```
Future<StorageTier?> chooseDownloadDestination(
  BuildContext context,
  Purity purity,
) {
  if (!context.mounted) return Future<StorageTier?>.value();
  return showDialog<StorageTier>(
    context: context,
    builder: (BuildContext context) => _DestinationDialog(purity: purity),
  );
}

/// The dialog body: a purity line when one is owed, then one card per tier.
class _DestinationDialog extends StatelessWidget {
  const _DestinationDialog({required this.purity});

  /// The purity of the wallpaper being downloaded, which decides both the
  /// options offered and whether the warning line appears.
  final Purity purity;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.detailDownloadChooseTier),
      content: _options(context, l10n),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
      ],
    );
  }

  /// Caps the measure at [_maxWidth] and scrolls rather than clipping.
  ///
  /// `AlertDialog` does not cap its own width, so on a tablet the cards would
  /// stretch to nearly the whole screen; the cap is intersected with the
  /// dialog's own constraints, so a narrow phone simply gets less than 360 and
  /// nothing overflows. The scroll is for three cards on a phone in landscape.
  Widget _options(BuildContext context, AppLocalizations l10n) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: <Widget>[
            ?_purityLine(context, l10n),
            for (final StorageTier tier in StorageSettings.choicesFor(purity))
              _destination(context, l10n, tier),
          ],
        ),
      ),
    );
  }

  /// Names the purity in the same tint the download button wears, or null for
  /// a safe wallpaper — which has nothing to warn about and gets no line.
  ///
  /// This is the legend the tint on the button deliberately does not carry: the
  /// button reminds, and the moment you act on the reminder, this says why.
  Widget? _purityLine(BuildContext context, AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);
    final Color? tint = purityAlertTint(theme.colorScheme, purity);
    if (tint == null) return null;
    return Row(
      spacing: 8,
      children: <Widget>[
        Icon(Icons.info_outline, size: 18, color: tint),
        Expanded(child: _purityText(theme, l10n, tint)),
      ],
    );
  }

  Widget _purityText(ThemeData theme, AppLocalizations l10n, Color tint) {
    return Text(
      purityLabel(l10n, purity),
      style: theme.textTheme.labelLarge?.copyWith(color: tint),
    );
  }

  /// One destination as a tappable card, in the app's own card language.
  Widget _destination(
    BuildContext context,
    AppLocalizations l10n,
    StorageTier tier,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pop(context, tier),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: _destinationRow(context, l10n, tier),
        ),
      ),
    );
  }

  Widget _destinationRow(
    BuildContext context,
    AppLocalizations l10n,
    StorageTier tier,
  ) {
    final ThemeData theme = Theme.of(context);
    return Row(
      spacing: 14,
      children: <Widget>[
        Icon(storageTierIcon(tier), color: theme.colorScheme.onSurfaceVariant),
        Expanded(child: _destinationText(theme, l10n, tier)),
      ],
    );
  }

  /// The name over its consequence — the detail line is the whole reason this
  /// is a card and not a menu row.
  Widget _destinationText(
    ThemeData theme,
    AppLocalizations l10n,
    StorageTier tier,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: <Widget>[
        Text(storageTierLabel(l10n, tier), style: theme.textTheme.titleMedium),
        Text(
          storageTierDetail(l10n, tier),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Wide enough for the longest destination detail on two lines, narrow
  /// enough that the cards still read as a stack of choices on a tablet.
  static const double _maxWidth = 360;
}
