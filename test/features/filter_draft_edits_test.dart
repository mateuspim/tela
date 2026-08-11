import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper_color.dart';
import 'package:tela/features/browse/filter_draft_edits.dart';

/// The filter sheet's own rules, asked directly.
///
/// These were `setState` bodies inside the sheet until the file went over the
/// line limit, so the only way to reach "the last purity chip stays on" was to
/// pump a modal and tap a chip. They are values in and values out now.
void main() {
  group('categories and purities keep at least one on', () {
    test('a second category joins the first', () {
      const SearchQuery draft = SearchQuery(
        categories: CategoryFilter(<Category>{Category.general}),
      );
      final SearchQuery next = withCategoryToggled(draft, Category.anime);
      expect(next.categories.categories, <Category>{
        Category.general,
        Category.anime,
      });
    });

    test('an unticked category comes off while another is on', () {
      const SearchQuery draft = SearchQuery(
        categories: CategoryFilter(<Category>{
          Category.general,
          Category.anime,
        }),
      );
      final SearchQuery next = withCategoryToggled(draft, Category.anime);
      expect(next.categories.categories, <Category>{Category.general});
    });

    /// Wallhaven's mask throws on `'000'`, so the sheet may not reach it.
    test('the last category cannot be turned off', () {
      const SearchQuery draft = SearchQuery(
        categories: CategoryFilter(<Category>{Category.general}),
      );
      final SearchQuery next = withCategoryToggled(draft, Category.general);
      expect(next.categories.categories, <Category>{Category.general});
    });

    test('the last purity cannot be turned off either', () {
      const SearchQuery draft = SearchQuery();
      final SearchQuery next = withPurityToggled(draft, Purity.sfw);
      expect(next.purity.purities, <Purity>{Purity.sfw});
    });
  });

  group('ratios may be emptied, unlike the masks', () {
    test('a shape goes on and comes off again', () {
      // Not the default query: `SearchQuery()` already carries the device's
      // own shape, and this is about what a tap adds and removes.
      const SearchQuery draft = SearchQuery(ratios: <RatioChoice>[]);
      final SearchQuery added = withRatioToggled(draft, ShapeRatio.portrait);
      expect(added.ratios, <RatioChoice>[ShapeRatio.portrait]);
      final SearchQuery removed = withRatioToggled(
        added,
        ShapeRatio.portrait,
      );
      expect(removed.ratios, isEmpty);
    });

    /// An empty `ratios` is how you ask Wallhaven for every shape, where an
    /// empty category mask is a 400.
    test('the last shape may be turned off', () {
      const SearchQuery draft = SearchQuery(
        ratios: <RatioChoice>[ShapeRatio.landscape],
      );
      expect(withRatioToggled(draft, ShapeRatio.landscape).ratios, isEmpty);
      expect(withRatiosCleared(draft).ratios, isEmpty);
    });
  });

  group('the colour is a radio, not a chip row', () {
    test('a second colour replaces the first', () {
      final SearchQuery draft = withColorChosen(
        const SearchQuery(),
        WallpaperColor.palette.first,
      );
      final SearchQuery next = withColorChosen(
        draft,
        WallpaperColor.palette[1],
      );
      expect(next.color, WallpaperColor.palette[1]);
    });

    /// Tapping the chosen swatch again is how you take it off without hunting
    /// for the "Any color" chip.
    test('choosing the current colour clears it', () {
      final SearchQuery draft = withColorChosen(
        const SearchQuery(),
        WallpaperColor.palette.first,
      );
      expect(
        withColorChosen(draft, WallpaperColor.palette.first).color,
        isNull,
      );
      expect(withColorChosen(draft, null).color, isNull);
    });
  });
}
