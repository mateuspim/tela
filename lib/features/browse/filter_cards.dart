import 'package:flutter/material.dart';
import 'package:tela/domain/models/source_capabilities.dart';

/// One group inside a filter card.
class FilterGroup extends StatelessWidget {
  /// Creates a titled group holding one filter control.
  const FilterGroup({required this.title, required this.child, super.key});

  /// What this axis is called.
  final String title;

  /// The control that edits it.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// A related set of filters, separated from the next concern by tonal depth.
class FilterCard extends StatelessWidget {
  /// Creates a card gathering [children] under one heading.
  const FilterCard({
    required this.icon,
    required this.title,
    required this.children,
    super.key,
  });

  /// The heading's icon.
  final IconData icon;

  /// What this group of filters is about.
  final String title;

  /// The groups inside, in order.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
          ),
          const Divider(),
          ...children,
        ],
      ),
    );
  }
}

/// Builds cards and groups against what the active source can actually be
/// asked for.
///
/// The filter sheet renders *from* [capabilities]. The failure mode being
/// designed out is the obvious alternative — offering a filter the source
/// cannot honour and silently dropping it, which looks to the user like the app
/// ignoring them. Withholding happens here, once, rather than at each of the
/// eight call sites.
///
/// ```dart
/// final FilterCards cards = FilterCards(source.capabilities);
/// cards.card(
///   icon: Icons.palette_outlined,
///   title: l10n.filterAppearanceGroup,
///   groups: <FilterGroup?>[
///     cards.group(SourceFilter.colors, l10n.filterColor, colorsControl),
///   ],
/// );
/// ```
class FilterCards {
  /// Builds against what [capabilities] says the source supports.
  const FilterCards(this.capabilities);

  /// What the active source can be asked for.
  final SourceCapabilities capabilities;

  /// One group, or nothing at all where the source has no such axis.
  FilterGroup? group(SourceFilter filter, String title, Widget child) {
    if (!capabilities.supports(filter)) return null;
    return FilterGroup(title: title, child: child);
  }

  /// One card, or nothing when every group in it was withheld — an empty card
  /// is a heading promising filters that are not there.
  FilterCard? card({
    required IconData icon,
    required String title,
    required List<FilterGroup?> groups,
  }) {
    final List<FilterGroup> present = groups.nonNulls.toList();
    if (present.isEmpty) return null;
    return FilterCard(icon: icon, title: title, children: present);
  }
}
