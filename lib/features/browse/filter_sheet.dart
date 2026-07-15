import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/browse_defaults.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/browse_filter_text.dart';
import 'package:tela/core/ui/screen_resolution.dart';
import 'package:tela/core/ui/wallpaper_swatch.dart';
import 'package:tela/core/ui/wallpaper_taxonomy_text.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/resolution_filter.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/search_tag.dart';
import 'package:tela/domain/models/wallpaper_color.dart';
import 'package:tela/features/browse/browse_query_controller.dart';
import 'package:tela/features/browse/resolution_filter_field.dart';
import 'package:tela/features/browse/tag_filter_field.dart';
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

  /// Filters scroll; the actions do not.
  ///
  /// The colour palette is 29 swatches tall, and with the buttons in the scroll
  /// view it pushed "Show wallpapers" off the bottom of the sheet — an apply
  /// button you have to go looking for is an apply button that doesn't get
  /// pressed. [Flexible] lets the list shrink to its content on a short sheet
  /// and scroll on a full one, with the actions pinned under it either way.
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              children: <Widget>[
                _FilterGroup(
                  title: l10n.filterCategories,
                  child: _categories(l10n),
                ),
                _FilterGroup(title: l10n.filterPurity, child: _purities(l10n)),
                _FilterGroup(title: l10n.filterTags, child: _tags()),
                _FilterGroup(title: l10n.filterRatio, child: _ratios(l10n)),
                _FilterGroup(
                  title: l10n.filterResolution,
                  child: _resolution(),
                ),
                _FilterGroup(title: l10n.filterColor, child: _colors(l10n)),
                _FilterGroup(title: l10n.filterOrder, child: _order(l10n)),
                _FilterGroup(
                  title: l10n.filterTopRange,
                  child: _topRange(l10n),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _actions(l10n),
          ),
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

  /// Chips, not a radio: Wallhaven unions the `ratios` param, so asking for
  /// `9x16` *and* `16x9` is one listing containing both — the opposite of
  /// `colors`, where a second value replaces the first.
  ///
  /// The device's own reduced shape leads, and is the recommendation: Wallhaven
  /// accepts an arbitrary `WxH`, so a phone that reduces to 9×20 can ask for
  /// exactly its own shape even though no standard dropdown offers one.
  ///
  /// "Any shape" leads the row and is selected whenever no chip is, so the row
  /// never reads as "nothing chosen yet" when it means "every shape".
  Widget _ratios(AppLocalizations l10n) {
    final ExactRatio screen = ExactRatio.ofScreen(screenResolution(context));
    final List<RatioChoice> selected = _draft.ratios;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        FilterChip(
          label: Text(l10n.ratioAny),
          selected: selected.isEmpty,
          onSelected: (bool _) => _clearRatios(),
        ),
        for (final RatioChoice choice in offerableRatios(
          screenResolution(context),
        ))
          FilterChip(
            label: Text(ratioLabel(l10n, choice, screen: screen)),
            selected: selected.contains(choice),
            onSelected: (bool _) => _toggleRatio(choice),
          ),
      ],
    );
  }

  /// The only filter tela builds a Wallhaven operator *for* the user, rather
  /// than picking from a fixed vocabulary: a typed name becomes `+name` /
  /// `-name`, folded into `q` beside whatever is in the search box.
  Widget _tags() {
    return TagFilterField(
      value: _draft.tags,
      onChanged: (List<SearchTag> tags) =>
          setState(() => _draft = _draft.copyWith(tags: tags)),
    );
  }

  /// The one filter that used to be imposed rather than chosen: `atleast` came
  /// from the device's own screen and could not be changed at all.
  Widget _resolution() {
    return ResolutionFilterField(
      value: _draft.resolution,
      onChanged: (ResolutionFilter resolution) =>
          setState(() => _draft = _draft.copyWith(resolution: resolution)),
    );
  }

  /// Wallhaven matches one colour at a time, so these are a radio, not chips:
  /// picking a second colour replaces the first rather than adding to it.
  ///
  /// "Any color" leads, and is selected whenever no swatch is — the row never
  /// reads as "no colour chosen yet" when it means "every colour".
  Widget _colors(AppLocalizations l10n) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        FilterChip(
          label: Text(l10n.filterColorAny),
          selected: _draft.color == null,
          onSelected: (bool _) => _chooseColor(null),
        ),
        for (final WallpaperColor color in WallpaperColor.palette)
          WallpaperSwatch(
            color: color,
            selected: _draft.color == color,
            onTap: () => _chooseColor(color),
          ),
      ],
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

  /// A [Wrap], not a [Row]: three buttons overflow a narrow phone, and an apply
  /// button that has fallen off the edge is one that does not get pressed (the
  /// same failure the pinned action bar was added to fix).
  Widget _actions(AppLocalizations l10n) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        TextButton.icon(
          onPressed: _saveAsDefault,
          icon: const Icon(Icons.push_pin_outlined),
          label: Text(l10n.filterSaveAsDefault),
        ),
        TextButton(onPressed: _reset, child: Text(l10n.filterReset)),
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

  /// Adds or removes one shape. Unlike the categories and the purities, the
  /// last chip *may* be turned off: an empty `ratios` is a legitimate request —
  /// it is how you ask Wallhaven for every shape — where an empty category mask
  /// is a 400.
  void _toggleRatio(RatioChoice choice) {
    final List<RatioChoice> next = <RatioChoice>[..._draft.ratios];
    if (!next.remove(choice)) next.add(choice);
    setState(() => _draft = _draft.copyWith(ratios: next));
  }

  void _clearRatios() {
    setState(() => _draft = _draft.copyWith(ratios: const <RatioChoice>[]));
  }

  /// Selects [color], or clears the filter when it is null or already selected.
  ///
  /// Tapping the chosen swatch again is how you take it off without hunting for
  /// the "Any color" chip.
  void _chooseColor(WallpaperColor? color) {
    final WallpaperColor? next = color == _draft.color ? null : color;
    setState(() => _draft = _draft.withColor(next));
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

  /// Keeps the draft as this device's defaults, and browses on it.
  ///
  /// Applies the draft first, so the purity the user picked for this session
  /// still lands: the saved snapshot deliberately carries no purity, so
  /// adopting it is not what would put a chosen "Sketchy" on screen. Saving
  /// also switches the source to this device — a "save these as my default"
  /// that left browse still opening on the account's would be a button that
  /// appears to do nothing.
  Future<void> _saveAsDefault() async {
    final SearchQuery saved = _draft;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String confirmation = AppLocalizations.of(
      context,
    ).filterSavedAsDefault;

    ref.read(browseQueryProvider.notifier).applyFilters(saved);
    Navigator.of(context).pop();
    await ref.read(browseDefaultsProvider.notifier).saveDeviceDefaults(saved);
    messenger.showSnackBar(SnackBar(content: Text(confirmation)));
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
