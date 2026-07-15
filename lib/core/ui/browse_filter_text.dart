/// The user-facing names of the browse filters.
///
/// In `core/ui` rather than `features/browse` because two features now render
/// the same filters: the filter sheet edits them, and Settings summarises them
/// under the browse-defaults switch. `core` may not import a feature
/// (CLAUDE.md), which is also why [RatioChoice] is a domain model.
library;

import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/resolution_filter.dart';
import 'package:tela/domain/models/search_query.dart';

/// The user-facing name of a [RatioChoice].
///
/// An exact ratio reads as `16×9` — a multiplication sign, not the API's
/// literal `x`. Pass [screen] to have the device's own shape name itself as the
/// recommendation it is; without it, it reads like any other ratio.
///
/// ```dart
/// ratioLabel(l10n, ShapeRatio.portrait); // 'Any portrait'
/// ```
String ratioLabel(
  AppLocalizations l10n,
  RatioChoice choice, {
  ExactRatio? screen,
}) {
  return switch (choice) {
    ShapeRatio.portrait => l10n.ratioPortrait,
    ShapeRatio.landscape => l10n.ratioLandscape,
    final ExactRatio ratio when ratio == screen => l10n.ratioScreen(
      '${ratio.width}',
      '${ratio.height}',
    ),
    final ExactRatio ratio => l10n.ratioExact(
      '${ratio.width}',
      '${ratio.height}',
    ),
  };
}

/// The user-facing name of one [Resolution], e.g. `1920×1080`.
///
/// Pass [screen] to have the device's own size name itself, for the same reason
/// the device's own ratio does: "exactly the screen I am holding" is the one
/// exact size a phone user is likely to want, and it is in no standard ladder.
///
/// The dimensions go in as **strings**, and every dimension placeholder in the
/// ARB is a `String` for the same reason: an `int` placeholder is rendered
/// through `NumberFormat`, which groups thousands — so a 1080x2400 phone read
/// back as `1,080×2,400`. A pixel count is a label, not a quantity.
String resolutionLabel(
  AppLocalizations l10n,
  Resolution size, {
  Resolution? screen,
}) {
  final String width = '${size.width}';
  final String height = '${size.height}';
  if (size == screen) return l10n.resolutionScreen(width, height);
  return l10n.resolutionValue(width, height);
}

/// How a whole resolution filter reads in a one-line summary.
String resolutionFilterLabel(AppLocalizations l10n, ResolutionFilter filter) {
  return switch (filter) {
    AutomaticResolution() => l10n.resolutionAutomatic,
    final AtLeastResolution at =>
      '${l10n.resolutionAtLeast} '
          '${resolutionLabel(l10n, at.minimum)}',
    final ExactResolutions exact =>
      exact.sizes
          .map((Resolution size) => resolutionLabel(l10n, size))
          .join(', '),
  };
}

/// How a whole ratio filter reads in a one-line summary, e.g. `9×20, 16×9`.
///
/// "Any shape" for the empty list, which is what an unfiltered listing means —
/// never an empty string, which would read as a summary that failed to load.
String ratiosLabel(AppLocalizations l10n, List<RatioChoice> ratios) {
  if (ratios.isEmpty) return l10n.ratioAny;
  return ratios
      .map((RatioChoice choice) => ratioLabel(l10n, choice))
      .join(', ');
}

/// The user-facing name of a [Sorting] — the label on its browse tab.
///
/// Exhaustive on purpose: a sorting Wallhaven adds later is a compile error
/// here rather than an unlabelled tab.
///
/// ```dart
/// sortingLabel(l10n, Sorting.dateAdded); // 'Latest'
/// ```
String sortingLabel(AppLocalizations l10n, Sorting sorting) {
  return switch (sorting) {
    Sorting.dateAdded => l10n.browseTabLatest,
    Sorting.toplist => l10n.browseTabTop,
    Sorting.hot => l10n.browseTabHot,
    Sorting.random => l10n.browseTabRandom,
    Sorting.views => l10n.browseTabViews,
    Sorting.favorites => l10n.browseTabFavorites,
    Sorting.relevance => l10n.browseTabRelevance,
  };
}

/// The user-facing name of a [SortOrder].
String orderLabel(AppLocalizations l10n, SortOrder order) {
  return switch (order) {
    SortOrder.desc => l10n.orderDescending,
    SortOrder.asc => l10n.orderAscending,
  };
}

/// The user-facing name of a [TopRange] window.
String topRangeLabel(AppLocalizations l10n, TopRange range) {
  return switch (range) {
    TopRange.oneDay => l10n.topRangeOneDay,
    TopRange.threeDays => l10n.topRangeThreeDays,
    TopRange.oneWeek => l10n.topRangeOneWeek,
    TopRange.oneMonth => l10n.topRangeOneMonth,
    TopRange.threeMonths => l10n.topRangeThreeMonths,
    TopRange.sixMonths => l10n.topRangeSixMonths,
    TopRange.oneYear => l10n.topRangeOneYear,
  };
}

/// How many filter groups differ from tela's opening browse query.
///
/// Search terms and sorting tabs are deliberately absent: both are already
/// visible in Browse. This count exists for the filter button, where it answers
/// the otherwise invisible question "did I leave something narrowed?".
int activeBrowseFilterCount(SearchQuery query) {
  const SearchQuery baseline = SearchQuery();
  return <bool>[
    query.categories.toApiBits() != baseline.categories.toApiBits(),
    query.purity.toApiBits() != baseline.purity.toApiBits(),
    !_sameFilterMembers(query.ratios, baseline.ratios),
    query.resolution != baseline.resolution,
    query.tags.isNotEmpty,
    query.color != null,
    query.order != baseline.order,
    query.topRange != baseline.topRange,
  ].where((bool active) => active).length;
}

bool _sameFilterMembers(Iterable<Object> a, Iterable<Object> b) {
  return a.length == b.length && a.toSet().containsAll(b);
}
