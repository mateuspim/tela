import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/tag_folder.dart';

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
    super.key,
  });

  /// The tag this download will use, or null for none.
  final TagFolder? selected;

  /// Tags that already exist as folders, offered as chips. Never includes the
  /// private library's; see the class docstring.
  final List<TagFolder> known;

  /// Called with the new tag, or null when *None* is chosen.
  final ValueChanged<TagFolder?> onChanged;

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
            for (final TagFolder tag in _offered) _tagChip(tag),
            _newChip(context, l10n),
          ],
        ),
      ],
    );
  }

  /// The chips to show: every known tag, plus the selected one when it is not
  /// among them.
  ///
  /// A tag typed a moment ago has no folder yet — nothing has been downloaded
  /// into it — so it would vanish from its own row the instant it was chosen
  /// without this.
  List<TagFolder> get _offered {
    final TagFolder? current = selected;
    if (current == null || known.contains(current)) return known;
    return <TagFolder>[current, ...known];
  }

  Widget _noneChip(AppLocalizations l10n) {
    return ChoiceChip(
      label: Text(l10n.downloadTagNone),
      selected: selected == null,
      onSelected: (bool _) => onChanged(null),
    );
  }

  Widget _tagChip(TagFolder tag) {
    return ChoiceChip(
      label: Text(tag.name),
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
