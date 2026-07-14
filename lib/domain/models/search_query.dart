import 'package:meta/meta.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/wallpaper_color.dart';

/// How Wallhaven orders results. The browse tabs are just three of these.
enum Sorting {
  /// Newest uploads first. The "Latest" tab.
  dateAdded('date_added'),

  /// Best match for the search term. Meaningless without one.
  relevance('relevance'),

  /// Shuffled. Pair with a seed or paging repeats itself.
  random('random'),

  /// Most-viewed of all time.
  views('views'),

  /// Most-favourited of all time.
  favorites('favorites'),

  /// Top-rated within a window — see [TopRange]. The "Top" tab.
  toplist('toplist'),

  /// Wallhaven's trending-now ranking. The "Hot" tab.
  hot('hot');

  const Sorting(this.apiValue);

  /// The literal the `sorting` query param expects.
  final String apiValue;

  /// Whether [SearchQuery.topRange] is meaningful — Wallhaven ignores it
  /// for every sorting but this one.
  bool get usesTopRange => this == Sorting.toplist;
}

/// Ascending or descending, for [Sorting].
enum SortOrder {
  /// Highest / newest first. The default everywhere in the app.
  desc('desc'),

  /// Lowest / oldest first.
  asc('asc');

  const SortOrder(this.apiValue);

  /// The literal the `order` query param expects.
  final String apiValue;
}

/// The window a `toplist` sorting looks back over.
enum TopRange {
  /// Last 24 hours.
  oneDay('1d'),

  /// Last 3 days.
  threeDays('3d'),

  /// Last week.
  oneWeek('1w'),

  /// Last month. Wallhaven's own default for toplist.
  oneMonth('1M'),

  /// Last 3 months.
  threeMonths('3M'),

  /// Last 6 months.
  sixMonths('6M'),

  /// Last year.
  oneYear('1y');

  const TopRange(this.apiValue);

  /// The literal the `topRange` query param expects. Case matters: `1M` is a
  /// month, `1m` is not a value Wallhaven accepts.
  final String apiValue;

  /// The range [raw] names, or null when it names none.
  ///
  /// Null rather than a throw: both callers read a value tela did not write
  /// this run — the account's `toplist_range` and the stored copy of it — and
  /// an unreadable one must cost the range, not the sync.
  static TopRange? tryFromApiValue(String raw) {
    return TopRange.values
        .where((TopRange range) => range.apiValue == raw)
        .firstOrNull;
  }
}

/// Everything that makes one Wallhaven listing different from another.
///
/// This is the single source of truth for a query — the browse tabs, the search
/// bar, and the filter sheet all produce one of these, and the API adapter's
/// only job is to encode it.
///
/// ```dart
/// const SearchQuery(sorting: Sorting.toplist, topRange: TopRange.oneWeek)
///     .toQueryParameters();
/// ```
@immutable
class SearchQuery {
  /// Creates a query. The defaults are the app's browse defaults: safe content,
  /// every category, newest first.
  const SearchQuery({
    this.term = '',
    this.categories = CategoryFilter.all,
    this.purity = PurityFilter.sfwOnly,
    this.sorting = Sorting.dateAdded,
    this.order = SortOrder.desc,
    this.topRange = TopRange.oneMonth,
    this.atLeast,
    this.ratios = const <RatioChoice>[ExactRatio(9, 16)],
    this.color,
    this.page = 1,
    this.seed,
  });

  /// Free-text search, including Wallhaven's operators (`+tag`, `-tag`,
  /// `like:{id}`). Empty means "browse", not "search for nothing".
  final String term;

  /// Which content buckets to include.
  final CategoryFilter categories;

  /// Which purities to include. NSFW here requires an API key, or the request
  /// comes back 401.
  final PurityFilter purity;

  /// Result ordering.
  final Sorting sorting;

  /// Direction of [sorting].
  final SortOrder order;

  /// Look-back window; only sent when [Sorting.usesTopRange].
  final TopRange topRange;

  /// Minimum acceptable resolution. Defaulted to the device screen so the grid
  /// isn't full of images too small for the phone.
  final Resolution? atLeast;

  /// Aspect ratios to accept, as a **union**: `[16x9, 9x16]` asks for both.
  /// Empty means no ratio filter at all. Portrait-first, because this is a
  /// phone.
  final List<RatioChoice> ratios;

  /// Dominant colour to match, from Wallhaven's fixed palette. Null means "any
  /// colour", which is not the same request as any particular one.
  final WallpaperColor? color;

  /// 1-based page number.
  final int page;

  /// Pins a `random` listing so paging through it doesn't reshuffle and show
  /// duplicates. Meaningless for every other sorting.
  final String? seed;

  /// Returns a copy with [page] replaced — the paging call, kept explicit so
  /// callers can't accidentally mutate the rest of the query while scrolling.
  SearchQuery atPage(int page) => copyWith(page: page);

  /// Returns a copy filtered by [color], or by no colour when it is null.
  ///
  /// Not a [copyWith] parameter, and that is the whole point: `copyWith` fills
  /// an omitted argument from `this`, so it cannot tell "leave the colour
  /// alone" apart from "clear the colour" — both arrive as null. Deselecting
  /// the swatch needs a call that means only the second thing.
  SearchQuery withColor(WallpaperColor? color) {
    return SearchQuery(
      term: term,
      categories: categories,
      purity: purity,
      sorting: sorting,
      order: order,
      topRange: topRange,
      atLeast: atLeast,
      ratios: ratios,
      color: color,
      page: page,
      seed: seed,
    );
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// An omitted field keeps its current value, so this cannot *clear* a
  /// nullable one — see [withColor].
  SearchQuery copyWith({
    String? term,
    CategoryFilter? categories,
    PurityFilter? purity,
    Sorting? sorting,
    SortOrder? order,
    TopRange? topRange,
    Resolution? atLeast,
    List<RatioChoice>? ratios,
    WallpaperColor? color,
    int? page,
    String? seed,
  }) {
    return SearchQuery(
      term: term ?? this.term,
      categories: categories ?? this.categories,
      purity: purity ?? this.purity,
      sorting: sorting ?? this.sorting,
      order: order ?? this.order,
      topRange: topRange ?? this.topRange,
      atLeast: atLeast ?? this.atLeast,
      ratios: ratios ?? this.ratios,
      color: color ?? this.color,
      page: page ?? this.page,
      seed: seed ?? this.seed,
    );
  }

  /// Value equality, which is what makes a query usable as *state*.
  ///
  /// The browse grid reloads when its query changes, and every rebuild hands it
  /// a freshly constructed one — so without this, identical filters would look
  /// like a new listing and re-fetch on every frame. The set and list fields
  /// need element-wise comparison; `==` on a `Set` is identity.
  @override
  bool operator ==(Object other) {
    return other is SearchQuery &&
        other.term == term &&
        _sameElements(other.categories.categories, categories.categories) &&
        _sameElements(other.purity.purities, purity.purities) &&
        other.sorting == sorting &&
        other.order == order &&
        other.topRange == topRange &&
        other.atLeast == atLeast &&
        _sameElements(other.ratios, ratios) &&
        other.color == color &&
        other.page == page &&
        other.seed == seed;
  }

  @override
  int get hashCode {
    return Object.hash(
      term,
      Object.hashAllUnordered(categories.categories),
      Object.hashAllUnordered(purity.purities),
      sorting,
      order,
      topRange,
      atLeast,
      Object.hashAllUnordered(ratios),
      color,
      page,
      seed,
    );
  }

  /// Set-like comparison: same members, order irrelevant.
  ///
  /// `ratios` is a list only because the API takes an ordered param; two
  /// queries asking for the same ratios in a different order are one listing.
  static bool _sameElements(Iterable<Object> a, Iterable<Object> b) {
    return a.length == b.length && a.toSet().containsAll(b);
  }

  /// Encodes to Wallhaven's `/search` query params.
  ///
  /// Note what is absent: the API key. It travels only in the `X-API-Key`
  /// header (CLAUDE.md, hard rule) so it can never leak into a logged URL.
  Map<String, String> toQueryParameters() {
    return <String, String>{
      if (term.isNotEmpty) 'q': term,
      'categories': categories.toApiBits(),
      'purity': purity.toApiBits(),
      'sorting': sorting.apiValue,
      'order': order.apiValue,
      if (sorting.usesTopRange) 'topRange': topRange.apiValue,
      if (atLeast != null) 'atleast': atLeast!.toApiValue(),
      'ratios': ?RatioChoice.encode(ratios),
      if (color != null) 'colors': color!.toApiValue(),
      'page': '$page',
      'seed': ?seed,
    };
  }
}
