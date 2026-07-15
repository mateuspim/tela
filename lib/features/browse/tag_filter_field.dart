import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/search_tag.dart';

/// Edits the list of tags a listing demands or forbids.
///
/// Its own widget rather than another method on the filter sheet, for the same
/// reason `ResolutionFilterField` is: it owns a text controller and so must be
/// stateful, where the sheet's other groups are all stateless chip rows.
///
/// A typed tag is added as a [TagSense.include], and a chip is *tapped* to flip
/// it to [TagSense.exclude] — so the input stays a single field, which keeps
/// the group short on a sheet that is already the tallest thing in the app.
class TagFilterField extends StatefulWidget {
  /// Creates the field, showing [value] and reporting edits via [onChanged].
  const TagFilterField({
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// The tags as they currently stand.
  final List<SearchTag> value;

  /// Called with the whole list the user has just edited.
  final ValueChanged<List<SearchTag>> onChanged;

  @override
  State<TagFilterField> createState() => _TagFilterFieldState();
}

class _TagFilterFieldState extends State<TagFilterField> {
  final TextEditingController _entry = TextEditingController();

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _hint(context, l10n),
        const SizedBox(height: 8),
        _field(l10n),
        if (widget.value.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _chips(context, l10n),
        ],
      ],
    );
  }

  Widget _hint(BuildContext context, AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);
    return Text(
      l10n.filterTagsHint,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _field(AppLocalizations l10n) {
    return TextField(
      controller: _entry,
      textInputAction: TextInputAction.done,
      onChanged: (String _) => setState(() {}),
      onSubmitted: (String _) => _add(),
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        hintText: l10n.filterTagFieldHint,
        suffixIcon: IconButton(
          icon: const Icon(Icons.add),
          tooltip: l10n.filterTagAdd,
          onPressed: _add,
        ),
      ),
    );
  }

  Widget _chips(BuildContext context, AppLocalizations l10n) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final SearchTag tag in widget.value)
          _TagChip(
            tag: tag,
            onFlip: () => _flip(tag),
            onRemove: () => _remove(tag),
          ),
      ],
    );
  }

  /// Adds the typed tag as an include, ignoring a blank entry or a name already
  /// filtered — the same name cannot sit in the query both demanded and
  /// forbidden, so a repeat is dropped rather than made contradictory. Flip the
  /// existing chip to change its sense.
  void _add() {
    final String name = _entry.text.trim();
    if (name.isEmpty || _alreadyFiltered(name)) {
      _entry.clear();
      return;
    }
    widget.onChanged(<SearchTag>[...widget.value, SearchTag(name)]);
    _entry.clear();
  }

  bool _alreadyFiltered(String name) {
    final String lower = name.toLowerCase();
    return widget.value.any((SearchTag tag) => tag.name.toLowerCase() == lower);
  }

  void _flip(SearchTag tag) {
    widget.onChanged(<SearchTag>[
      for (final SearchTag each in widget.value)
        if (each == tag) each.flipped() else each,
    ]);
  }

  void _remove(SearchTag tag) {
    widget.onChanged(<SearchTag>[
      for (final SearchTag each in widget.value)
        if (each != tag) each,
    ]);
  }
}

/// One tag as a chip: an icon for its sense, a tap to flip it, a delete to drop
/// it. An excluded tag is tinted with the error colour, so "hide this" reads as
/// a warning rather than as just another selected chip.
class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.tag,
    required this.onFlip,
    required this.onRemove,
  });

  final SearchTag tag;
  final VoidCallback onFlip;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool excluded = tag.sense == TagSense.exclude;
    return InputChip(
      avatar: Icon(excluded ? Icons.remove : Icons.add),
      label: Text(tag.name),
      tooltip: excluded ? l10n.filterTagExclude : l10n.filterTagInclude,
      backgroundColor: excluded ? colors.errorContainer : null,
      onPressed: onFlip,
      onDeleted: onRemove,
      deleteButtonTooltipMessage: l10n.filterTagRemove(tag.name),
    );
  }
}
