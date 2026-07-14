/// The user-facing names of the browse filters.
///
/// In `core/ui` rather than `features/browse` because two features now render
/// the same filters: the filter sheet edits them, and Settings summarises them
/// under the browse-defaults switch. `core` may not import a feature
/// (CLAUDE.md), which is also why [RatioChoice] is a domain model.
library;

import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/search_query.dart';

/// The user-facing name of a [RatioChoice].
///
/// ```dart
/// ratioLabel(l10n, RatioChoice.portrait); // 'Portrait'
/// ```
String ratioLabel(AppLocalizations l10n, RatioChoice choice) {
  return switch (choice) {
    RatioChoice.portrait => l10n.ratioPortrait,
    RatioChoice.landscape => l10n.ratioLandscape,
    RatioChoice.any => l10n.ratioAny,
  };
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
