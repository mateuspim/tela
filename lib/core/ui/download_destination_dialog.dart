import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/purity_alert_tint.dart';
import 'package:tela/core/ui/storage_tier_text.dart';
import 'package:tela/core/ui/wallpaper_taxonomy_text.dart';
import 'package:tela/domain/models/download_destination_streak.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';

/// One download's answer: where it lands, and whether that becomes the default.
///
/// [remember] is only ever true for the streak destination — it is the "Always
/// save … here" affordance, which both sends this download there *and* asks the
/// caller to persist it as the bucket's default. A plain destination tap leaves
/// it false: this one download moves, the setting does not.
@immutable
class DownloadDestinationChoice {
  /// Creates a choice of [tier], optionally asking to [remember] it as default.
  const DownloadDestinationChoice({required this.tier, this.remember = false});

  /// Where this download should land.
  final StorageTier tier;

  /// Whether to also make [tier] the default for this wallpaper's bucket.
  final bool remember;
}

/// Asks where this one download should land; null when dismissed.
///
/// Centred, not a bottom sheet — which is what it replaces. The three
/// destinations differ in *consequence*, not in name (one is indexed into
/// Photos, one is reachable over USB, one is visible to nothing but tela), so
/// this is a decision to be read rather than a menu to be flicked at.
///
/// When a [streak] of recent downloads has drifted from [configuredTier] —
/// where a plain tap already routes — the chooser says so: it marks that spot
/// and offers to make it the default, which is what stops the long-pressing. A
/// streak that merely agrees with [configuredTier] is nothing to suggest and is
/// left silent.
///
/// The option list comes from [StorageSettings.choicesFor] rather than being
/// spelled out here: that is where the NSFW invariant lives, and it is why an
/// explicit wallpaper is never offered the gallery.
///
/// ```dart
/// final DownloadDestinationChoice? choice = await chooseDownloadDestination(
///   context,
///   purity: wallpaper.purity,
///   configuredTier: settings.tierFor(wallpaper.purity),
///   streak: streak,
/// );
/// ```
Future<DownloadDestinationChoice?> chooseDownloadDestination(
  BuildContext context, {
  required Purity purity,
  required StorageTier configuredTier,
  DownloadDestinationStreak? streak,
}) {
  if (!context.mounted) {
    return Future<DownloadDestinationChoice?>.value();
  }
  return showDialog<DownloadDestinationChoice>(
    context: context,
    builder: (BuildContext context) => _DestinationDialog(
      purity: purity,
      configuredTier: configuredTier,
      streak: streak,
    ),
  );
}

/// The dialog body: a purity line when one is owed, then one card per tier, and
/// an "Always save … here" action when a run has drifted from the default.
class _DestinationDialog extends StatelessWidget {
  const _DestinationDialog({
    required this.purity,
    required this.configuredTier,
    required this.streak,
  });

  /// The purity of the wallpaper being downloaded, which decides the options,
  /// the warning line, and how the "Always" action names itself.
  final Purity purity;

  /// Where a plain tap already routes this purity; the streak is only worth
  /// mentioning when it differs from this.
  final StorageTier configuredTier;

  /// The run of recent same-destination downloads, or null when there is none.
  final DownloadDestinationStreak? streak;

  /// A destination has to be reached this many times in a row before the
  /// chooser offers to make it the default. The owner's number.
  static const int _suggestAfter = 3;

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
  /// dialog's own constraints, so a narrow phone gets less than 360 and nothing
  /// overflows. The scroll is for three cards on a phone in landscape.
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
            ?_alwaysAction(context, l10n),
          ],
        ),
      ),
    );
  }

  /// The destination a run has been going to, when that run is long enough to
  /// suggest and is *not* already where a plain tap routes — null otherwise.
  ///
  /// The one gated case is deliberately left out: making explicit downloads
  /// default to files-outside-gallery can tip them onto a removable card, which
  /// carries a warning that lives in Settings. The chooser still saves there
  /// for one download; it just does not offer to make it permanent from here.
  StorageTier? get _suggestedTier {
    final DownloadDestinationStreak? run = streak;
    if (run == null || run.length < _suggestAfter) return null;
    if (run.tier == configuredTier) return null;
    final bool gatedInSettings =
        StorageSettings.bucketFor(purity) == Purity.nsfw &&
        run.tier == StorageTier.filesOutsideGallery;
    return gatedInSettings ? null : run.tier;
  }

  /// Names the purity in the same tint the download button wears, or null for
  /// a safe wallpaper — which has nothing to warn about and gets no line.
  Widget? _purityLine(BuildContext context, AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);
    final Color? tint = purityAlertTint(theme.colorScheme, purity);
    if (tint == null) return null;
    return Row(
      spacing: 8,
      children: <Widget>[
        Icon(Icons.info_outline, size: 18, color: tint),
        Expanded(
          child: Text(
            purityLabel(l10n, purity),
            style: theme.textTheme.labelLarge?.copyWith(color: tint),
          ),
        ),
      ],
    );
  }

  /// One destination as a tappable card, marked when the run has been landing
  /// there.
  Widget _destination(
    BuildContext context,
    AppLocalizations l10n,
    StorageTier tier,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pop(
          context,
          DownloadDestinationChoice(tier: tier),
        ),
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
  /// is a card and not a menu row — with the streak note when this is the tier
  /// the run has been going to.
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
        ?_streakNote(theme, l10n, tier),
      ],
    );
  }

  /// "Last N saved here", but only on the tier the suggestion points at.
  Widget? _streakNote(
    ThemeData theme,
    AppLocalizations l10n,
    StorageTier tier,
  ) {
    if (tier != _suggestedTier) return null;
    return Text(
      l10n.detailDownloadStreak(streak!.length),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.primary,
      ),
    );
  }

  /// The "Always save … here" button, present only when there is a suggestion.
  ///
  /// Because the chooser is only ever reached by a deliberate long press, this
  /// is never an unsolicited nag: it waits in the sheet the user chose to open,
  /// and disappears the moment they take it (the default then equals the run)
  /// or route elsewhere (the run resets). So it needs no dismiss-cooldown.
  Widget? _alwaysAction(BuildContext context, AppLocalizations l10n) {
    final StorageTier? tier = _suggestedTier;
    if (tier == null) return null;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => Navigator.pop(
          context,
          DownloadDestinationChoice(tier: tier, remember: true),
        ),
        icon: const Icon(Icons.push_pin_outlined, size: 18),
        label: Text(l10n.detailDownloadAlways(purityLabel(l10n, purity))),
      ),
    );
  }

  /// Wide enough for the longest destination detail on two lines, narrow
  /// enough that the cards still read as a stack of choices on a tablet.
  static const double _maxWidth = 360;
}
