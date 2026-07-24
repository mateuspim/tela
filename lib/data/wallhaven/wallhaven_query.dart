import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/resolution_filter.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/search_tag.dart';
import 'package:tela/domain/models/wallpaper_color.dart';

/// Encodes a [SearchQuery] the way Wallhaven's `/search` wants it.
///
/// This is the whole of tela's knowledge of Wallhaven's URL shape, and it lives
/// here rather than on the query model because a second source encodes the same
/// query completely differently: Konachan has no `sorting`, `order`,
/// `categories`, `purity`, `width` or `ratio` param at all — every one of them
/// is a token inside one `tags` string (PLAN §18.3).
///
/// Note what is absent: the API key. It travels only in the `X-API-Key` header
/// (CLAUDE.md, hard rule) so it can never leak into a logged URL.
///
/// ```dart
/// wallhavenQueryParameters(const SearchQuery())['purity']; // '100'
/// ```
Map<String, String> wallhavenQueryParameters(SearchQuery query) {
  return <String, String>{
    'q': ?_freeQuery(query),
    'categories': wallhavenCategoryBits(query.categories),
    'purity': wallhavenPurityBits(query.purity),
    'sorting': query.sorting.apiValue,
    'order': query.order.apiValue,
    if (query.sorting.usesTopRange) 'topRange': query.topRange.apiValue,
    ..._resolutionParameters(query.resolution),
    'ratios': ?RatioChoice.encode(query.ratios),
    if (query.color case final WallpaperColor color)
      'colors': _colorValue(color),
    'page': '${query.page}',
    'seed': ?query.seed,
  };
}

/// The `q` value: the free-text term with the tag tokens folded in after it, or
/// null when there is nothing to search.
///
/// Null rather than `''` on purpose — the same distinction the colour and ratio
/// params draw: an *absent* `q` is a browse, where an empty `q=` is a search
/// for the empty string. `sunset` plus a `+nature` tag reads
/// `sunset +"nature"`; the tag alone reads `+"nature"`, which Wallhaven
/// accepts as a leading sign.
///
/// The term goes out *alone*, with the tags and the blocklist withheld, when it
/// is one of Wallhaven's two query-replacing operators — see
/// [_isExclusiveOperator].
String? _freeQuery(SearchQuery query) {
  if (_isExclusiveOperator(query.term)) return query.term;
  final List<String> parts = <String>[
    if (query.term.isNotEmpty) query.term,
    for (final SearchTag tag in query.tags) _tagToken(tag),
    // Same encoding as the chosen tags, not a hand-rolled `-$name`: Wallhaven
    // needs the quotes a multi-word tag name requires, and this is the one
    // place that gets that right.
    for (final String name in query.blockedTagNames)
      _tagToken(SearchTag(name, TagSense.exclude)),
  ];
  return parts.isEmpty ? null : parts.join(' ');
}

/// Whether [term] is one of Wallhaven's two operators that *replace* the whole
/// query rather than compose with it.
///
/// Confirmed live against Wallhaven, 2026-07-15: `id:{n}` and `like:{id}`
/// return **zero** results the instant anything else shares `q` with them — a
/// tag, a blocked tag's `-name`, even bare free text. `@user`, `+tag`, `-tag`,
/// and plain keywords all compose normally; only these two don't. This is why
/// following a tag chip (which searches `id:{n}`) went blank the moment a
/// single tag was blocked: the blocklist was silently turning every exact-tag
/// lookup into a self-contradicting, zero-result query.
bool _isExclusiveOperator(String term) =>
    term.startsWith('id:') || term.startsWith('like:');

/// The `q` fragment for one tag, e.g. `+"nature"` or `-"people"`.
///
/// Always quoted, even for a single word: confirmed live against Wallhaven
/// (2026-07-15) that an *unquoted* multi-word name like `-anime girls` parses
/// as `-anime` (exclude) plus a bare `girls` (weak "should match"), not as
/// excluding the one tag — and two of those stacked can crush a listing to near
/// zero. Quoting a single word costs nothing (`+"nature"` and `+nature` return
/// identical results) so there is no case worth special-casing.
///
/// Konachan wants the opposite treatment of the very same [SearchTag] —
/// underscores joining the words and **no** quotes — which is the clearest
/// reason a tag cannot serialise itself.
String _tagToken(SearchTag tag) => '${tag.sense.sign}"${tag.name}"';

/// The size params, which are two and must never travel together.
///
/// Sent together, `atleast` wins and `resolutions` is silently ignored — the
/// conflict the sealed [ResolutionFilter] exists to make unrepresentable.
Map<String, String> _resolutionParameters(ResolutionFilter filter) {
  return switch (filter) {
    // Unresolved: the screen has not answered yet, so no size param at all.
    AutomaticResolution() => const <String, String>{},
    AtLeastResolution(:final Resolution minimum) => <String, String>{
      'atleast': minimum.toApiValue(),
    },
    ExactResolutions(:final List<Resolution> sizes) => <String, String>{
      'resolutions': sizes
          .map((Resolution size) => size.toApiValue())
          .join(','),
    },
  };
}

/// The `colors` param, which takes the hex with no leading `#`.
String _colorValue(WallpaperColor color) => color.hex.substring(1);

/// Encodes the purity set as the 3-bit `purity` param.
///
/// Bit order is fixed by the API: `sfw sketchy nsfw`, so `"100"` is sfw-only
/// and `"111"` is everything.
String wallhavenPurityBits(PurityFilter purity) {
  return _bits(
    Purity.values,
    purity.purities,
    'purity filter must select at least one of sfw|sketchy|nsfw, got none',
  );
}

/// Encodes the category set as the 3-bit `categories` param, in the fixed order
/// `general anime people`.
String wallhavenCategoryBits(CategoryFilter categories) {
  return _bits(
    Category.values,
    categories.categories,
    'category filter must select at least one of general|anime|people, '
    'got none',
  );
}

/// One of Wallhaven's fixed-width masks over [values].
///
/// Throws on an empty selection rather than sending `"000"`, which Wallhaven
/// answers with a 400 — a filter that selects nothing is a bug upstream, not a
/// wider listing.
String _bits<T extends Enum>(List<T> values, Set<T> selected, String empty) {
  final String bits = values
      .map((T v) => selected.contains(v) ? '1' : '0')
      .join();
  if (bits == '0' * values.length) throw ArgumentError(empty);
  return bits;
}
