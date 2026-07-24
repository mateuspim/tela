import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/purity_alert_tint.dart';
import 'package:tela/core/ui/storage_tier_text.dart';
import 'package:tela/core/ui/wallpaper_taxonomy_text.dart';
import 'package:tela/domain/models/download_destination_streak.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';

/// One download's answer: where it lands, and whether that answer sticks.
///
/// [remember] is only ever true for the streak destination — the "Always
/// save … here" affordance, which both sends this download there *and* asks the
/// caller to persist it as the bucket's per-purity default (I3). [pin] is the
/// "Keep sending here" toggle: it asks the caller to make [tier] the
/// purity-flat pin every later download follows (K2). A plain destination tap
/// leaves both false: this one download moves, nothing else does.
///
/// A choice that only [stopsPin] carries a null [tier] and downloads nothing —
/// it is the chooser's Stop affordance, clearing an active pin and no more.
@immutable
class DownloadDestinationChoice {
  /// Creates a choice of [tier], optionally asking to [remember] or [pin] it.
  const DownloadDestinationChoice({
    required this.tier,
    this.remember = false,
    this.pin = false,
  });

  /// A choice that only clears the "Keep sending here" pin — nothing downloads.
  const DownloadDestinationChoice.stopPin()
    : tier = null,
      remember = false,
      pin = false;

  /// Where this download should land, or null when the choice only [stopsPin].
  final StorageTier? tier;

  /// Whether to also make [tier] the per-purity configured default (I3's
  /// "Always"). Independent of [pin].
  final bool remember;

  /// Whether to make [tier] the purity-flat "Keep sending here" pin (K2).
  final bool pin;

  /// Whether this choice only clears the pin and downloads nothing — true
  /// exactly when [tier] is null.
  bool get stopsPin => tier == null;
}

/// Asks where this one download should land; null when dismissed.
///
/// Centred, not a bottom sheet. The three destinations differ in *consequence*,
/// not in name (one is indexed into Photos, one is reachable over USB, one is
/// visible to nothing but tela), so this is a decision to be read rather than a
/// menu to be flicked at.
///
/// When a [streak] of recent downloads has drifted from [configuredTier] —
/// where a plain tap already routes — it marks that spot and offers to make
/// it the default, which is what stops the long-pressing. A "Keep sending here"
/// switch pins the tapped tier for *every* later download; [pinnedTier] is the
/// pin already in force, which the chooser shows and offers to clear.
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
///   pinnedTier: pin,
/// );
/// ```
Future<DownloadDestinationChoice?> chooseDownloadDestination(
  BuildContext context, {
  required Purity purity,
  required StorageTier configuredTier,
  DownloadDestinationStreak? streak,
  StorageTier? pinnedTier,
}) {
  return _show(
    context,
    options: StorageSettings.choicesFor(purity),
    strongestPurity: purity,
    configuredTier: configuredTier,
    streak: streak,
    pinnedTier: pinnedTier,
  );
}

/// Asks where a whole selection should land; null when dismissed.
///
/// The batch twin of [chooseDownloadDestination]: it offers only the tiers
/// legal for **every** purity in [purities] (the intersection), so a mixed set
/// containing an explicit wallpaper is never offered the gallery and one
/// destination genuinely governs all of them. It has no streak or "Always" — a
/// bulk action is not a per-item habit — but it does carry the "Keep sending
/// here" switch, since pinning is exactly a "put everything here" decision.
///
/// [count] is how many wallpapers this one answer governs, and it goes in the
/// heading: the bare "Download to" of the single chooser made a nine-item batch
/// look like one download, with no hint that the tap moves all nine.
Future<DownloadDestinationChoice?> chooseBatchDownloadDestination(
  BuildContext context, {
  required Set<Purity> purities,
  required int count,
  StorageTier? pinnedTier,
}) {
  return _show(
    context,
    options: StorageSettings.choicesForAll(purities),
    strongestPurity: _strongest(purities),
    configuredTier: null,
    streak: null,
    pinnedTier: pinnedTier,
    batchCount: count,
  );
}

/// The most explicit purity in [purities] — the one whose warning the chooser
/// shows over a mixed batch — or [Purity.sfw] for an empty set.
Purity _strongest(Set<Purity> purities) {
  return purities.fold(
    Purity.sfw,
    (Purity worst, Purity p) => p.index > worst.index ? p : worst,
  );
}

Future<DownloadDestinationChoice?> _show(
  BuildContext context, {
  required List<StorageTier> options,
  required Purity strongestPurity,
  required StorageTier? configuredTier,
  required DownloadDestinationStreak? streak,
  required StorageTier? pinnedTier,
  int? batchCount,
}) {
  if (!context.mounted) {
    return Future<DownloadDestinationChoice?>.value();
  }
  return showDialog<DownloadDestinationChoice>(
    context: context,
    builder: (BuildContext context) => _DestinationDialog(
      options: options,
      strongestPurity: strongestPurity,
      configuredTier: configuredTier,
      streak: streak,
      pinnedTier: pinnedTier,
      batchCount: batchCount,
    ),
  );
}

/// The dialog body: a purity line when one is owed, the active pin when there
/// is one, a card per destination, the "Always" action when a run has drifted,
/// and the "Keep sending here" switch.
class _DestinationDialog extends StatefulWidget {
  const _DestinationDialog({
    required this.options,
    required this.strongestPurity,
    required this.configuredTier,
    required this.streak,
    required this.pinnedTier,
    this.batchCount,
  });

  /// The tiers to offer, already narrowed to what every purity present allows.
  final List<StorageTier> options;

  /// The purity that decides the warning line and the "Always" label — the most
  /// explicit one in a batch.
  final Purity strongestPurity;

  /// Where a plain tap already routes, or null for a batch (which has no single
  /// configured tier); the streak is only worth mentioning when it differs.
  final StorageTier? configuredTier;

  /// The run of recent same-destination downloads, or null (always null for a
  /// batch).
  final DownloadDestinationStreak? streak;

  /// The "Keep sending here" pin already in force, or null when none is set.
  final StorageTier? pinnedTier;

  /// How many wallpapers this answer governs, or null for a single download —
  /// which needs no count, since the thing being placed is the one on screen.
  final int? batchCount;

  @override
  State<_DestinationDialog> createState() => _DestinationDialogState();
}

class _DestinationDialogState extends State<_DestinationDialog> {
  /// Whether the tapped destination should become the pin. Opt-in, so it
  /// starts off — except when a pin is already in force, where it mirrors that
  /// state so the switch reads the truth.
  late bool _keepSending = widget.pinnedTier != null;

  /// A destination has to be reached this many times in a row before the
  /// chooser offers to make it the default. The owner's number.
  static const int _suggestAfter = 3;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(_title(l10n)),
      content: _content(context, l10n),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        ?_stopAction(context, l10n),
      ],
    );
  }

  /// "Download to" for one wallpaper; "Download 9 wallpapers to" for a batch.
  ///
  /// The count is the only thing on screen that says how far the tap reaches —
  /// the cards below name destinations, not quantities.
  String _title(AppLocalizations l10n) {
    final int? count = widget.batchCount;
    if (count == null) return l10n.detailDownloadChooseTier;
    return l10n.batchDownloadChooseTier(count);
  }

  /// Caps the measure at [_maxWidth] and scrolls rather than clipping, since an
  /// `AlertDialog` does not cap its own width and would stretch on a tablet.
  Widget _content(BuildContext context, AppLocalizations l10n) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: <Widget>[
            ?_purityLine(context, l10n),
            ?_pinLine(context, l10n),
            for (final StorageTier tier in widget.options)
              _destination(context, l10n, tier),
            ?_alwaysAction(context, l10n),
            _keepSendingSwitch(context, l10n),
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
    final DownloadDestinationStreak? run = widget.streak;
    final StorageTier? configured = widget.configuredTier;
    if (run == null || configured == null) return null;
    if (run.length < _suggestAfter || run.tier == configured) return null;
    final bool gatedInSettings =
        StorageSettings.bucketFor(widget.strongestPurity) == Purity.nsfw &&
        run.tier == StorageTier.filesOutsideGallery;
    return gatedInSettings ? null : run.tier;
  }

  /// Names the purity in the same tint the download button wears, or null for a
  /// safe wallpaper — which has nothing to warn about and gets no line.
  Widget? _purityLine(BuildContext context, AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);
    final Purity purity = widget.strongestPurity;
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

  /// The pin already in force, named so the user knows every download is being
  /// steered — or null when there is no pin. The Stop affordance lives in the
  /// dialog actions, not here.
  Widget? _pinLine(BuildContext context, AppLocalizations l10n) {
    final StorageTier? pin = widget.pinnedTier;
    if (pin == null) return null;
    final ThemeData theme = Theme.of(context);
    return Row(
      spacing: 8,
      children: <Widget>[
        Icon(Icons.push_pin, size: 18, color: theme.colorScheme.primary),
        Expanded(
          child: Text(
            l10n.downloadPinActive(storageTierLabel(l10n, pin)),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  /// One destination as a tappable card, marked when the run has been landing
  /// there. Tapping answers the tier and whether it becomes the pin.
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
          DownloadDestinationChoice(tier: tier, pin: _keepSending),
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
      l10n.detailDownloadStreak(widget.streak!.length),
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
  Widget? _alwaysAction(BuildContext context, AppLocalizations l10n) {
    final StorageTier? tier = _suggestedTier;
    if (tier == null || widget.pinnedTier != null) return null;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => Navigator.pop(
          context,
          DownloadDestinationChoice(tier: tier, remember: true),
        ),
        icon: const Icon(Icons.tune, size: 18),
        label: Text(
          l10n.detailDownloadMakeDefault(
            purityLabel(l10n, widget.strongestPurity),
          ),
        ),
      ),
    );
  }

  /// The "Keep sending here" toggle. When on, tapping a destination pins it for
  /// every later download; when off, the tap is a one-off and leaves any pin as
  /// it is (Stop clears an existing one).
  Widget _keepSendingSwitch(BuildContext context, AppLocalizations l10n) {
    return SwitchListTile.adaptive(
      value: _keepSending,
      onChanged: (bool on) => setState(() => _keepSending = on),
      contentPadding: EdgeInsets.zero,
      title: Text(l10n.downloadKeepSendingHere),
      subtitle: Text(l10n.downloadKeepSendingSubtitle),
    );
  }

  /// The Stop button, present only while a pin is in force. It clears the pin
  /// and downloads nothing — the way out that does not make you save something.
  Widget? _stopAction(BuildContext context, AppLocalizations l10n) {
    if (widget.pinnedTier == null) return null;
    return TextButton(
      onPressed: () => Navigator.pop(
        context,
        const DownloadDestinationChoice.stopPin(),
      ),
      child: Text(l10n.downloadPinStop),
    );
  }

  /// Wide enough for the longest destination detail on two lines, narrow enough
  /// that the cards still read as a stack of choices on a tablet.
  static const double _maxWidth = 360;
}
