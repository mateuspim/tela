import 'package:meta/meta.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';

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
    this.ratios = const <String>['9x16'],
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

  /// Aspect ratios, e.g. `9x16`. Portrait-first, because this is a phone.
  final List<String> ratios;

  /// 1-based page number.
  final int page;

  /// Pins a `random` listing so paging through it doesn't reshuffle and show
  /// duplicates. Meaningless for every other sorting.
  final String? seed;

  /// Returns a copy with [page] replaced — the paging call, kept explicit so
  /// callers can't accidentally mutate the rest of the query while scrolling.
  SearchQuery atPage(int page) => copyWith(page: page);

  /// Returns a copy with the given fields replaced.
  SearchQuery copyWith({
    String? term,
    CategoryFilter? categories,
    PurityFilter? purity,
    Sorting? sorting,
    SortOrder? order,
    TopRange? topRange,
    Resolution? atLeast,
    List<String>? ratios,
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
      if (ratios.isNotEmpty) 'ratios': ratios.join(','),
      'page': '$page',
      'seed': ?seed,
    };
  }
}
