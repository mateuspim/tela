/// Every edit the filter sheet makes to its draft, as plain functions over a
/// [SearchQuery].
///
/// The sheet edits a draft and applies it in one write, so each of these is
/// a value in and a value out — no `setState`, no controller, nothing to mock.
/// That is the point of them living here: the rules below are the only logic in
/// the sheet, and pinning "the last purity chip cannot be turned off" should
/// not cost a pumped modal.
///
/// ```dart
/// setState(() => _draft = withCategoryToggled(_draft, Category.anime));
/// ```
library;

import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper_color.dart';
import 'package:tela/features/browse/browse_query_controller.dart';

/// Adds or removes [category], keeping at least one on.
///
/// Wallhaven's category mask throws on `'000'`, so an empty selection is not
/// a state the sheet may reach — see [toggledChoice].
SearchQuery withCategoryToggled(SearchQuery draft, Category category) {
  final Set<Category> next = toggledChoice(
    draft.categories.categories,
    category,
  );
  return draft.copyWith(categories: CategoryFilter(next));
}

/// Adds or removes [purity], keeping at least one on, for the same reason
/// [withCategoryToggled] does.
SearchQuery withPurityToggled(SearchQuery draft, Purity purity) {
  final Set<Purity> next = toggledChoice(draft.purity.purities, purity);
  return draft.copyWith(purity: PurityFilter(next));
}

/// Adds or removes one shape.
///
/// Unlike the categories and the purities, the last chip *may* be turned off:
/// an empty `ratios` is a legitimate request — it is how you ask Wallhaven for
/// every shape — where an empty category mask is a 400.
SearchQuery withRatioToggled(SearchQuery draft, RatioChoice choice) {
  final List<RatioChoice> next = <RatioChoice>[...draft.ratios];
  if (!next.remove(choice)) next.add(choice);
  return draft.copyWith(ratios: next);
}

/// Asks for every shape again.
SearchQuery withRatiosCleared(SearchQuery draft) =>
    draft.copyWith(ratios: const <RatioChoice>[]);

/// Selects [color], or clears the filter when it is null or already selected.
///
/// Tapping the chosen swatch again is how you take it off without hunting for
/// the "Any color" chip.
SearchQuery withColorChosen(SearchQuery draft, WallpaperColor? color) {
  return draft.withColor(color == draft.color ? null : color);
}
