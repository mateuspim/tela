import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_taxonomy_text.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/features/browse/browse_filter_text.dart';
import 'package:tela/features/browse/browse_query_controller.dart';
import 'package:tela/features/settings/api_key_controller.dart';

/// Opens the filter sheet over the browse grid.
///
/// It edits a *draft* and applies it in one write, unlike the settings screen:
/// every applied query is a Wallhaven request out of the 45/min budget, so five
/// toggles must not cost five listings.
///
/// ```dart
/// await showFilterSheet(context);
/// ```
Future<void> showFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => const FilterSheet(),
  );
}

/// The category / purity / order / range / ratio filters, as one draft.
class FilterSheet extends ConsumerStatefulWidget {
  /// Creates the sheet, seeded from the query the grids are showing now.
  const FilterSheet({super.key});

  @override
  ConsumerState<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<FilterSheet> {
  late SearchQuery _draft = ref.read(browseQueryProvider);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: <Widget>[
          _FilterGroup(title: l10n.filterCategories, child: _categories(l10n)),
          _FilterGroup(title: l10n.filterPurity, child: _purities(l10n)),
          _FilterGroup(title: l10n.filterRatio, child: _ratios(l10n)),
          _FilterGroup(title: l10n.filterOrder, child: _order(l10n)),
          _FilterGroup(title: l10n.filterTopRange, child: _topRange(l10n)),
          const SizedBox(height: 8),
          _actions(l10n),
        ],
      ),
    );
  }

  Widget _categories(AppLocalizations l10n) {
    final Set<Category> selected = _draft.categories.categories;
    return Wrap(
      spacing: 8,
      children: <Widget>[
        for (final Category category in Category.values)
          FilterChip(
            label: Text(categoryLabel(l10n, category)),
            selected: selected.contains(category),
            onSelected: (bool _) => _toggleCategory(category),
          ),
      ],
    );
  }

  /// NSFW appears only with a stored key — see [offerablePurities].
  Widget _purities(AppLocalizations l10n) {
    final bool hasKey = ref.watch(apiKeyProvider).value ?? false;
    final Set<Purity> selected = _draft.purity.purities;
    return Wrap(
      spacing: 8,
      children: <Widget>[
        for (final Purity purity in offerablePurities(hasApiKey: hasKey))
          FilterChip(
            label: Text(purityLabel(l10n, purity)),
            selected: selected.contains(purity),
            onSelected: (bool _) => _togglePurity(purity),
          ),
      ],
    );
  }

  Widget _ratios(AppLocalizations l10n) {
    return SegmentedButton<RatioChoice>(
      segments: <ButtonSegment<RatioChoice>>[
        for (final RatioChoice choice in RatioChoice.values)
          ButtonSegment<RatioChoice>(
            value: choice,
            label: Text(ratioLabel(l10n, choice)),
          ),
      ],
      selected: <RatioChoice>{RatioChoice.of(_draft)},
      onSelectionChanged: _chooseRatio,
    );
  }

  Widget _order(AppLocalizations l10n) {
    return SegmentedButton<SortOrder>(
      segments: <ButtonSegment<SortOrder>>[
        for (final SortOrder order in SortOrder.values)
          ButtonSegment<SortOrder>(
            value: order,
            label: Text(orderLabel(l10n, order)),
          ),
      ],
      selected: <SortOrder>{_draft.order},
      onSelectionChanged: (Set<SortOrder> chosen) =>
          setState(() => _draft = _draft.copyWith(order: chosen.single)),
    );
  }

  /// Wallhaven ignores this outside the Top tab, and the hint says so rather
  /// than the control vanishing when you switch tabs.
  Widget _topRange(AppLocalizations l10n) {
    return DropdownButtonFormField<TopRange>(
      initialValue: _draft.topRange,
      decoration: InputDecoration(helperText: l10n.filterTopRangeHint),
      items: <DropdownMenuItem<TopRange>>[
        for (final TopRange range in TopRange.values)
          DropdownMenuItem<TopRange>(
            value: range,
            child: Text(topRangeLabel(l10n, range)),
          ),
      ],
      onChanged: _chooseTopRange,
    );
  }

  Widget _actions(AppLocalizations l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        TextButton(onPressed: _reset, child: Text(l10n.filterReset)),
        const SizedBox(width: 8),
        FilledButton(onPressed: _apply, child: Text(l10n.filterApply)),
      ],
    );
  }

  void _toggleCategory(Category category) {
    final Set<Category> next = toggledChoice(
      _draft.categories.categories,
      category,
    );
    setState(() => _draft = _draft.copyWith(categories: CategoryFilter(next)));
  }

  void _togglePurity(Purity purity) {
    final Set<Purity> next = toggledChoice(_draft.purity.purities, purity);
    setState(() => _draft = _draft.copyWith(purity: PurityFilter(next)));
  }

  void _chooseRatio(Set<RatioChoice> chosen) {
    setState(() => _draft = _draft.copyWith(ratios: chosen.single.ratios));
  }

  void _chooseTopRange(TopRange? range) {
    if (range == null) return;
    setState(() => _draft = _draft.copyWith(topRange: range));
  }

  void _apply() {
    ref.read(browseQueryProvider.notifier).applyFilters(_draft);
    Navigator.of(context).pop();
  }

  void _reset() {
    ref.read(browseQueryProvider.notifier).clearFilters();
    Navigator.of(context).pop();
  }
}

/// A titled row of controls.
class _FilterGroup extends StatelessWidget {
  const _FilterGroup({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
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
