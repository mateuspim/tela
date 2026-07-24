import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/resolution_filter.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/search_tag.dart';

/// The two hosts Konachan serves the *same* post database on.
///
/// `.net` is a server-enforced `rating:s` view of `.com` — same ids, same
/// wallpapers, but explicit content is excluded by the server rather than by a
/// tag string we assembled (PLAN §18.2). Browsing SFW-only goes to `.net` so a
/// bug in tela's rating mapping cannot leak an explicit image into a safe
/// browse: `.net` will not serve one at any price.
abstract final class KonachanHost {
  /// The safe-only host. A `rating:e` or `rating:q` query here returns `[]`.
  static const String safe = 'konachan.net';

  /// The unrestricted host, which serves every rating anonymously.
  static const String unrestricted = 'konachan.com';

  /// Which host answers a browse for [purity].
  ///
  /// SFW-only → the safe host, as defence in depth; anything wider needs the
  /// unrestricted one, since `.net` cannot be talked into serving `q` or `e`.
  static String forPurity(PurityFilter purity) =>
      purity.purities.contains(Purity.sketchy) ||
          purity.purities.contains(Purity.nsfw)
      ? unrestricted
      : safe;
}

/// How many posts one page requests. A page shorter than this means the end of
/// the listing — Konachan publishes no page count (PLAN §18.1), so this is also
/// how `KonachanMapper` decides `hasMore`.
const int konachanPageSize = 40;

/// Encodes a [SearchQuery] the way Konachan's `/post.json` wants it.
///
/// This is the whole of tela's knowledge of Konachan's URL shape, and it is
/// nothing like Wallhaven's: there is no `sorting`, `order`, `categories`,
/// `purity`, `width` or `ratio` param — **every filter is a token inside one
/// `tags` string** (PLAN §18.3), which is exactly why the encoder lives here
/// and not on the query model.
///
/// ```dart
/// // The browse default is safe-only, portrait-first:
/// konachanQueryParameters(const SearchQuery())['tags']; // 'rating:s ratio:9:16'
/// ```
Map<String, String> konachanQueryParameters(SearchQuery query) {
  return <String, String>{
    'tags': _tags(query),
    'limit': '$konachanPageSize',
    'page': '${query.page}',
  };
}

/// The whole `tags` value: every filter folded into one space-joined string.
///
/// Empty is legal and means "browse everything" — no rating token is the "all
/// three purities" case (PLAN §18.3), so an empty result is not an error.
String _tags(SearchQuery query) {
  final List<String> tokens = <String>[
    if (query.term.isNotEmpty) query.term,
    if (query.uploader.isNotEmpty) 'user:${_slug(query.uploader)}',
    for (final SearchTag tag in query.tags) _tagToken(tag),
    for (final String name in query.blockedTagNames) '-${_slug(name)}',
    ?_ratingToken(query.purity),
    ..._resolutionTokens(query.resolution),
    ..._ratioTokens(query.ratios),
    ?_orderToken(query.sorting),
  ];
  return tokens.join(' ');
}

/// One tag as Konachan spells it — `black_hair` or `-black_hair`.
///
/// Underscores joining the words and **no** quotes, the exact opposite of
/// `SearchTag.token`'s treatment for Wallhaven (which quotes a multi-word name
/// so it doesn't split into two tokens). One `SearchTag` cannot serialise
/// itself correctly for both, which is why §17 moved the encoder off the model.
String _tagToken(SearchTag tag) =>
    '${tag.sense == TagSense.exclude ? '-' : ''}${_slug(tag.name)}';

/// Spaces become underscores; Konachan tags are underscore-joined.
String _slug(String name) => name.trim().replaceAll(' ', '_');

/// The single `rating:` term for a purity set, positive or negative.
///
/// One `rating:` token per selected purity is **silently wrong** — Konachan
/// does not OR them, and `rating:s rating:q` returns only questionable, the
/// last token simply winning (verified live, PLAN §18.3). All seven non-empty
/// subsets are one token; the all-three case is *no* token, so this returns
/// null there. Throws on the empty set, which no filter should ever produce.
String? _ratingToken(PurityFilter purity) {
  final Set<Purity> wanted = purity.purities;
  final bool s = wanted.contains(Purity.sfw);
  final bool q = wanted.contains(Purity.sketchy);
  final bool e = wanted.contains(Purity.nsfw);
  return switch ((s, q, e)) {
    (true, false, false) => 'rating:s',
    (false, true, false) => 'rating:q',
    (false, false, true) => 'rating:e',
    (true, true, false) => '-rating:e',
    (true, false, true) => '-rating:q',
    (false, true, true) => '-rating:s',
    (true, true, true) => null,
    (false, false, false) => throw ArgumentError(
      'purity filter must select at least one of sfw|sketchy|nsfw, got none',
    ),
  };
}

/// A minimum size as `width:>=W height:>=H`, or nothing.
///
/// Only [AtLeastResolution] maps — it is the shape `forScreen` produces and the
/// one PLAN §18.3 verified. Konachan has no exact-size list, so
/// [ExactResolutions] is dropped rather than mis-encoded into a query that
/// would quietly return the wrong grid.
List<String> _resolutionTokens(ResolutionFilter filter) {
  return switch (filter) {
    AutomaticResolution() || ExactResolutions() => const <String>[],
    AtLeastResolution(:final Resolution minimum) => <String>[
      'width:>=${minimum.width}',
      'height:>=${minimum.height}',
    ],
  };
}

/// One `ratio:W:H` token per exact ratio.
///
/// [ShapeRatio]'s `portrait`/`landscape` keywords have no Konachan equivalent
/// and are dropped: the site only understands an exact `ratio:`. The default
/// query carries a single ratio, which is the case §18.3 verified.
List<String> _ratioTokens(List<RatioChoice> ratios) {
  return <String>[
    for (final RatioChoice choice in ratios)
      if (choice is ExactRatio) 'ratio:${choice.width}:${choice.height}',
  ];
}

/// The `order:` token for a sorting, or nothing for the default.
///
/// Newest-first is Konachan's default and needs no token; views and favorites
/// both fold onto `order:score`, the only ranking Konachan exposes. Every other
/// sorting is declared unsupported in the capabilities, so it never reaches
/// here — `order:random` in particular takes no seed and would repeat images
/// across pages (PLAN §18.3).
String? _orderToken(Sorting sorting) {
  return switch (sorting) {
    Sorting.dateAdded => null,
    Sorting.views || Sorting.favorites => 'order:score',
    Sorting.relevance ||
    Sorting.random ||
    Sorting.toplist ||
    Sorting.hot => throw ArgumentError(
      'Konachan does not support ${sorting.name} sorting; it is declared '
      'unsupported in SourceCapabilities and must never reach the encoder',
    ),
  };
}
