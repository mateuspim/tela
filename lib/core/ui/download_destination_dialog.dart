import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/download_destination_card.dart';
import 'package:tela/core/ui/download_destination_choice.dart';
import 'package:tela/core/ui/download_tag_field.dart';
import 'package:tela/core/ui/purity_alert_tint.dart';
import 'package:tela/core/ui/storage_tier_text.dart';
import 'package:tela/core/ui/wallpaper_taxonomy_text.dart';
import 'package:tela/domain/models/download_destination_streak.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/use_cases/suggest_tag_folders.dart';

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
  TagFolder? suggestedTag,
  List<TagFolder> knownTags = const <TagFolder>[],
  Future<List<TagCandidate>>? tagSuggestions,
}) {
  return _show(
    context,
    options: StorageSettings.choicesFor(purity),
    strongestPurity: purity,
    configuredTier: configuredTier,
    streak: streak,
    pinnedTier: pinnedTier,
    suggestedTag: suggestedTag,
    knownTags: knownTags,
    tagSuggestions: tagSuggestions,
    // One wallpaper needs no share counts: "1/1" on every chip says nothing.
    selectionSize: 0,
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
  TagFolder? suggestedTag,
  List<TagFolder> knownTags = const <TagFolder>[],
  Future<List<TagCandidate>>? tagSuggestions,
}) {
  return _show(
    context,
    options: StorageSettings.choicesForAll(purities),
    strongestPurity: _strongest(purities),
    configuredTier: null,
    streak: null,
    pinnedTier: pinnedTier,
    suggestedTag: suggestedTag,
    knownTags: knownTags,
    tagSuggestions: tagSuggestions,
    selectionSize: count,
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
  required TagFolder? suggestedTag,
  required List<TagFolder> knownTags,
  required Future<List<TagCandidate>>? tagSuggestions,
  required int selectionSize,
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
      suggestedTag: suggestedTag,
      knownTags: knownTags,
      tagSuggestions: tagSuggestions,
      selectionSize: selectionSize,
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
    required this.suggestedTag,
    required this.knownTags,
    required this.tagSuggestions,
    required this.selectionSize,
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

  /// The tag to start on — the one remembered from the last tagged download,
  /// or null. Selected rather than merely listed, so the common case of filing
  /// a run of wallpapers under one tag is the same single tap it was before.
  final TagFolder? suggestedTag;

  /// Tags that already exist as folders in the shared tiers, offered as chips.
  final List<TagFolder> knownTags;

  /// The wallpapers' own tags, ranked — in flight when the dialog opens.
  ///
  /// A future rather than a value, because reading them can cost requests and
  /// the dialog must not wait: it opens on what is free (the search's tag, the
  /// folders that exist) and fills the rest in when they land.
  final Future<List<TagCandidate>>? tagSuggestions;

  /// How many wallpapers the suggestions are counted over.
  final int selectionSize;

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

  /// The tag this download will carry, starting from the remembered one.
  late TagFolder? _tag = widget.suggestedTag;

  /// Whether to keep offering [_tag] next time. On when the chooser opened
  /// already holding a tag, so the switch reads the state that is really in
  /// force rather than proposing to undo it.
  late bool _keepTag = widget.suggestedTag != null;

  /// The ranked suggestions once they arrive, empty until then.
  List<TagCandidate> _suggestions = const <TagCandidate>[];

  /// Whether the lookup is still running, for the quiet line under the chips.
  late bool _readingTags = widget.tagSuggestions != null;

  @override
  void initState() {
    super.initState();
    unawaited(_awaitSuggestions());
  }

  /// Takes the suggestions when they land, and starts on the best one unless
  /// the user has already answered.
  ///
  /// **Only when nothing is selected yet.** A remembered tag, or one the user
  /// tapped while the lookup was in flight, is an answer — and a dialog that
  /// changed its own selection out from under someone mid-tap would be worse
  /// than one that suggested nothing at all.
  Future<void> _awaitSuggestions() async {
    final Future<List<TagCandidate>>? pending = widget.tagSuggestions;
    if (pending == null) return;
    final List<TagCandidate> ranked = await pending;
    if (!mounted) return;
    setState(() {
      _suggestions = ranked;
      _readingTags = false;
      if (_tag == null && _untouched && ranked.isNotEmpty) {
        _tag = ranked.first.tag;
        _keepTag = false;
      }
    });
  }

  /// Whether the user has left the tag row alone since the dialog opened.
  bool _untouched = true;

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
              _destination(context, tier),
            ?_alwaysAction(context, l10n),
            const Divider(height: 8),
            DownloadTagField(
              selected: _tag,
              known: widget.knownTags,
              suggestions: _suggestions,
              selectionSize: widget.selectionSize,
              loadingSuggestions: _readingTags,
              onChanged: (TagFolder? tag) => setState(() {
                _untouched = false;
                _tag = tag;
                // Remembering nothing is not a state worth offering: the switch
                // means "offer this next time", and there is no this.
                if (tag == null) _keepTag = false;
              }),
            ),
            ?_keepTagSwitch(context, l10n),
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

  /// One destination as a tappable card. Tapping answers everything the dialog
  /// has collected: the tier, the tag, and whether either should stick.
  Widget _destination(BuildContext context, StorageTier tier) {
    return DownloadDestinationCard(
      tier: tier,
      streak: widget.streak,
      suggestedTier: _suggestedTier,
      onTap: () => Navigator.pop(
        context,
        DownloadDestinationChoice(
          tier: tier,
          pin: _keepSending,
          tag: _tag,
          rememberTag: _keepTag,
        ),
      ),
    );
  }

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
  /// The tag's "keep offering this" switch, or nothing when no tag is chosen.
  ///
  /// Absent rather than disabled: a switch for remembering nothing has no state
  /// worth reading, and the row it would sit in is the one place the dialog is
  /// already asking two questions at once.
  Widget? _keepTagSwitch(BuildContext context, AppLocalizations l10n) {
    if (_tag == null) return null;
    return SwitchListTile.adaptive(
      value: _keepTag,
      onChanged: (bool on) => setState(() => _keepTag = on),
      contentPadding: EdgeInsets.zero,
      title: Text(l10n.downloadTagKeep),
    );
  }

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
