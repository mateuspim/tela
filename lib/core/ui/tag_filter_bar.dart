import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/tag_folder.dart';

/// Which tag a library shelf is currently narrowed to.
///
/// UI vocabulary, not a domain concept — the same footing `WallpaperMark` is on
/// in `core/ui/wallpaper_marks_scope.dart`. The domain has downloads that carry
/// a tag; this is only the question of which of them a screen shows.
///
/// **Untagged is a filter, not the absence of one.** A library that has been
/// tagged for a while accumulates a pile of older files in the tier root, and
/// "show me the ones I never filed" is exactly the question someone tidying up
/// asks. Folding it into [TagFilter.all] would make that pile unreachable.
@immutable
class TagFilter {
  const TagFilter._(this._tag, this._untaggedOnly);

  /// Everything, tagged or not — what a shelf opens on.
  const TagFilter.all() : this._(null, false);

  /// Only what sits in the tier's root, filed under nothing.
  const TagFilter.untagged() : this._(null, true);

  /// Only what is filed under [tag].
  const TagFilter.of(TagFolder tag) : this._(tag, false);

  final TagFolder? _tag;
  final bool _untaggedOnly;

  /// Whether a download filed under [tag] belongs on screen.
  bool matches(TagFolder? tag) {
    if (_untaggedOnly) return tag == null;
    final TagFolder? wanted = _tag;
    return wanted == null || tag == wanted;
  }

  /// Whether this filter narrows anything at all.
  bool get isAll => _tag == null && !_untaggedOnly;

  @override
  bool operator ==(Object other) =>
      other is TagFilter &&
      other._tag == _tag &&
      other._untaggedOnly == _untaggedOnly;

  @override
  int get hashCode => Object.hash(_tag, _untaggedOnly);
}

/// The chip row that narrows a library shelf to one tag.
///
/// Shown only when there is more than one thing to choose between: a library
/// with no tags in it at all gets no row, because a filter offering exactly
/// "everything" is a control that cannot do anything.
///
/// Horizontally scrollable rather than wrapping. A wrapping row of twenty tags
/// would push the grid off the screen, and the grid is what the user came for.
class TagFilterBar extends StatelessWidget {
  /// Creates the row over [tags], with [selected] active.
  const TagFilterBar({
    required this.tags,
    required this.selected,
    required this.onChanged,
    required this.hasUntagged,
    super.key,
  });

  /// Every tag in use on this shelf, in the order they should appear.
  final List<TagFolder> tags;

  /// The filter in force.
  final TagFilter selected;

  /// Called with the newly chosen filter.
  final ValueChanged<TagFilter> onChanged;

  /// Whether anything on this shelf is untagged — the *Untagged* chip is
  /// pointless on a shelf where everything is filed.
  final bool hasUntagged;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: <Widget>[
          _chip(l10n.tagFilterAll, const TagFilter.all()),
          for (final TagFolder tag in tags) _chip(tag.name, TagFilter.of(tag)),
          if (hasUntagged)
            _chip(l10n.tagFilterUntagged, const TagFilter.untagged()),
        ],
      ),
    );
  }

  Widget _chip(String label, TagFilter filter) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: ChoiceChip(
          label: Text(label),
          selected: selected == filter,
          // Re-tapping the active chip clears back to everything, so getting
          // out of a filter never needs a hunt for the All chip.
          onSelected: (bool _) =>
              onChanged(selected == filter ? const TagFilter.all() : filter),
        ),
      ),
    );
  }
}
