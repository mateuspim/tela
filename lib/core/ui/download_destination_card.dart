import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/storage_tier_text.dart';
import 'package:tela/domain/models/download_destination_streak.dart';
import 'package:tela/domain/models/storage_tier.dart';

/// One destination's row inside the download chooser: its icon, its name, what
/// choosing it actually means, and the note when a run has been landing there.
///
/// Split out of `download_destination_dialog.dart` when the tag row pushed that
/// file past the 500-line limit. It earns its own file rather than being the
/// first thing to hand: this is the part that explains a *consequence* — one
/// tier is indexed into Photos, one is reachable over USB, one is visible to
/// nothing but tela — while the dialog around it is about collecting an answer.
class DownloadDestinationCard extends StatelessWidget {
  /// Creates the row for [tier].
  const DownloadDestinationCard({
    required this.tier,
    required this.streak,
    required this.suggestedTier,
    required this.onTap,
    super.key,
  });

  /// The destination this row offers.
  final StorageTier tier;

  /// The run of recent downloads to one destination, or null when there is
  /// none worth mentioning.
  final DownloadDestinationStreak? streak;

  /// The tier the chooser is suggesting as a new default, if any — the one
  /// this row marks with its note.
  final StorageTier? suggestedTier;

  /// Chooses this destination.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: _row(context, l10n),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);
    return Row(
      spacing: 14,
      children: <Widget>[
        Icon(storageTierIcon(tier), color: theme.colorScheme.onSurfaceVariant),
        Expanded(child: _text(theme, l10n)),
      ],
    );
  }

  /// The name over its consequence — the detail line is the whole reason this
  /// is a card and not a menu row — with the streak note when this is the tier
  /// the run has been going to.
  Widget _text(ThemeData theme, AppLocalizations l10n) {
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
        ?_note(theme, l10n, tier),
      ],
    );
  }

  /// "Last N saved here", but only on the tier the suggestion points at.
  Widget? _note(
    ThemeData theme,
    AppLocalizations l10n,
    StorageTier tier,
  ) {
    if (tier != suggestedTier) return null;
    return Text(
      l10n.detailDownloadStreak(streak!.length),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.primary,
      ),
    );
  }

  /// The "Make this the default for …" button, present only when there is a
  /// suggestion and no pin is in force.
  ///
  /// Because the chooser is only ever reached by a deliberate long press, this
  /// is never an unsolicited nag: it waits in the sheet the user chose to open,
  /// and disappears the moment they take it or route elsewhere.
  ///
  /// It deliberately wears neither the pin icon nor the pin's words. Two
  /// different promises were reading as one: this sets the *per-purity default*
  /// (I3, the same value Settings writes), while the switch below sets the
  /// purity-flat *pin* (K2). A pin also outranks the default — so while one is
  /// in force this stands down entirely rather than offer a change the user
  /// would not see until they Stop.
}
