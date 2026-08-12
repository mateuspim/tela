import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/use_cases/suggest_tag_folders.dart';

/// The tag row inside the download chooser: which folder this download is
/// filed under.
///
/// Its own widget rather than more of `download_destination_dialog.dart`,
/// which is already near the file limit — and because the thing it does is
/// separable: the dialog answers *where* a download goes (a tier, with a purity
/// rule behind it) and this answers *what it is filed as* (a folder, with no
/// rule behind it at all).
///
/// **Suggestions are the shared tiers' folders only.** This dialog opens from
/// the browse wall, which has no app-lock in front of it, and the private
/// library's folder names say roughly what its file paths say. A private
/// download can still be tagged — by typing, or by the tag already remembered
/// for it — it just is not offered a list of what the private library contains
/// on an ungated screen.
///
/// ```dart
/// DownloadTagField(
///   selected: tag,
///   known: knownTags,
///   onChanged: (TagFolder? tag) => setState(() => _tag = tag),
/// );
/// ```
class DownloadTagField extends StatelessWidget {
  /// Creates the tag row over the [known] folders, with [selected] chosen.
  const DownloadTagField({
    required this.selected,
    required this.known,
    required this.onChanged,
    this.suggestions = const <TagCandidate>[],
    this.selectionSize = 0,
    this.loadingSuggestions = false,
    super.key,
  });

  /// The tag this download will use, or null for none.
  final TagFolder? selected;

  /// Tags that already exist as folders, offered as chips. Never includes the
  /// private library's; see the class docstring.
  final List<TagFolder> known;

  /// Called with the new tag, or null when *None* is chosen.
  final ValueChanged<TagFolder?> onChanged;

  /// Tags the selected wallpapers themselves carry, best first. Empty until
  /// the lookup lands — the row renders without them rather than waiting.
  final List<TagCandidate> suggestions;

  /// How many wallpapers the suggestions were counted over — the `10` in
  /// `8/10`. Zero hides the counts, which is right for a single download,
  /// where "1 of 1" says nothing.
  final int selectionSize;

  /// Whether more suggestions are still being read. Shown as a quiet line, not
  /// a spinner over the dialog: the destination decision is the one the user
  /// came for, and it must never be blocked on the network.
  final bool loadingSuggestions;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: <Widget>[
        Text(l10n.downloadTagLabel, style: theme.textTheme.labelLarge),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _noneChip(l10n),
            for (final TagCandidate candidate in _candidates)
              _tagChip(candidate.tag, _shareLabel(l10n, candidate)),
            for (final TagFolder tag in _extras) _tagChip(tag, null),
            _newChip(context, l10n),
          ],
        ),
        if (loadingSuggestions)
          Text(
            l10n.downloadTagReading,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  /// The ranked suggestions, or the plain folder list before any arrive.
  ///
  /// Before the lookup lands there is still something worth offering — the
  /// folders that already exist — so the row is never empty and never waits.
  List<TagCandidate> get _candidates {
    if (suggestions.isNotEmpty) return suggestions;
    return <TagCandidate>[
      for (final TagFolder tag in known)
        TagCandidate(tag: tag, origin: TagCandidateOrigin.existingFolder),
    ];
  }

  /// Anything selected that no chip above covers.
  ///
  /// A tag typed a moment ago has no folder yet — nothing has been downloaded
  /// into it — so it would vanish from its own row the instant it was chosen
  /// without this.
  List<TagFolder> get _extras {
    final TagFolder? current = selected;
    if (current == null) return const <TagFolder>[];
    final bool shown = _candidates.any((TagCandidate c) => c.tag == current);
    return shown ? const <TagFolder>[] : <TagFolder>[current];
  }

  /// `8/10` for a tag the selection carries, and nothing for one that came
  /// from the search or from an existing folder — where a count would be a
  /// number about nothing.
  String? _shareLabel(AppLocalizations l10n, TagCandidate candidate) {
    if (candidate.origin != TagCandidateOrigin.selection) return null;
    if (candidate.share <= 0 || selectionSize <= 0) return null;
    return l10n.downloadTagShare(candidate.share, selectionSize);
  }

  Widget _noneChip(AppLocalizations l10n) {
    return ChoiceChip(
      label: Text(l10n.downloadTagNone),
      selected: selected == null,
      onSelected: (bool _) => onChanged(null),
    );
  }

  Widget _tagChip(TagFolder tag, String? share) {
    return ChoiceChip(
      label: Text(share == null ? tag.name : '${tag.name}  $share'),
      selected: selected == tag,
      onSelected: (bool _) => onChanged(tag),
    );
  }

  /// Opens the naming dialog. An `ActionChip`, not a `ChoiceChip`: it performs
  /// something rather than being one of the states this row can rest in.
  Widget _newChip(BuildContext context, AppLocalizations l10n) {
    return ActionChip(
      avatar: const Icon(Icons.add, size: 18),
      label: Text(l10n.downloadTagNew),
      onPressed: () async {
        final TagFolder? named = await askForTagFolder(context);
        if (named != null) onChanged(named);
      },
    );
  }
}

/// Asks for a new tag name; null when dismissed or left empty.
///
/// Shared with the retag action, which asks exactly the same question of a
/// selection that is already downloaded.
///
/// Validates as the user types rather than on submit, because the rule is not
/// guessable — a name may hold spaces but not begin with one, and may hold no
/// `.` at all — and a dialog that accepts a name then refuses it on the way to
/// disk is the worse of the two ways to say so.
Future<TagFolder?> askForTagFolder(BuildContext context) {
  return showDialog<TagFolder>(
    context: context,
    builder: (BuildContext context) => const _NameTagDialog(),
  );
}

class _NameTagDialog extends StatefulWidget {
  const _NameTagDialog();

  @override
  State<_NameTagDialog> createState() => _NameTagDialogState();
}

class _NameTagDialogState extends State<_NameTagDialog> {
  final TextEditingController _controller = TextEditingController();

  /// What is typed so far, or null while it could not be a folder.
  TagFolder? get _typed {
    final String raw = _controller.text;
    return TagFolder.isLegal(raw) ? TagFolder(raw) : null;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TagFolder? typed = _typed;
    return AlertDialog(
      title: Text(l10n.downloadTagNewTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: TagFolder.maxLength,
        decoration: InputDecoration(
          labelText: l10n.downloadTagLabel,
          helperText: l10n.downloadTagRule,
          errorText: _controller.text.isEmpty || typed != null
              ? null
              : l10n.downloadTagRule,
        ),
        onChanged: (String _) => setState(() {}),
        onSubmitted: (String _) {
          if (typed != null) Navigator.pop(context, typed);
        },
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        TextButton(
          onPressed: typed == null ? null : () => Navigator.pop(context, typed),
          child: Text(l10n.downloadTagUse),
        ),
      ],
    );
  }
}
