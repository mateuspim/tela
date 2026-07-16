import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/browse_filter_text.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/features/browse/browse_filter_scope.dart';
import 'package:tela/features/browse/filter_sheet.dart';

/// The app-bar control that opens the filter sheet, badged with how many
/// filters are on.
///
/// Shared by Browse and the linked listings rather than private to Browse: a
/// tag listing with no way to filter it was a filter button that existed on one
/// screen by accident of where it was written.
///
/// ```dart
/// BrowseFilterButton(
///   filters: query,
///   scope: ref.read(browseQueryProvider.notifier),
/// )
/// ```
class BrowseFilterButton extends StatelessWidget {
  /// Creates the button over the [scope] it filters.
  const BrowseFilterButton({
    required this.filters,
    required this.scope,
    super.key,
  });

  /// The query the badge counts. Passed in rather than read off [scope] so the
  /// caller's own `watch` is what rebuilds the count.
  final SearchQuery filters;

  /// Where the sheet reads and writes — Browse's filters, or one listing's.
  final BrowseFilterScope scope;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int active = activeBrowseFilterCount(filters);
    return IconButton.filledTonal(
      icon: ExcludeSemantics(
        child: Badge(
          isLabelVisible: active > 0,
          label: Text('$active'),
          child: const Icon(Icons.tune),
        ),
      ),
      tooltip: active == 0
          ? l10n.browseFilters
          : l10n.browseFiltersActive(active),
      onPressed: () => showFilterSheet(context, scope: scope),
    );
  }
}
