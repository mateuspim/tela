import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_capabilities.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_collection.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';

/// In-memory [WallpaperSource] that records what it was asked for.
///
/// Records every [SearchQuery] it receives so tests can assert on the request
/// the use case *built*, which is where the seed and paging bugs live.
class FakeWallpaperSource implements WallpaperSource {
  /// Creates a fake that answers every search with [page], or throws [failure].
  FakeWallpaperSource({
    this.id = SourceId.wallhaven,
    this.displayName = 'Wallhaven',
    this.capabilities = wallhavenLikeCapabilities,
    this.page,
    this.pageFor,
    this.pagesByNumber = const <int, WallpaperPage>{},
    this.details,
    this.detailsById = const <String, WallpaperDetails>{},
    this.account,
    this.collections = const <String, List<WallpaperCollection>>{},
    this.collectionPages = const <String, WallpaperPage>{},
    this.failure,
    this.detailFailure,
    this.searchDelay,
    this.idIn = _recognizesNothing,
  });

  /// Which source this stands in for. Defaults to Wallhaven, because that is
  /// what nearly every existing test is exercising.
  @override
  final SourceId id;

  /// The name a switcher would print.
  @override
  final String displayName;

  /// What this fake claims to support.
  ///
  /// The seam's real test: a fake declaring *fewer* capabilities is what proves
  /// the filter sheet and the search guard read them rather than assuming
  /// Wallhaven's.
  @override
  final SourceCapabilities capabilities;

  /// The collections each username owns, keyed by username.
  ///
  /// A username absent from the map is one the source has never heard of, and
  /// [collectionsOf] throws [NotFoundFailure] for it — the same answer
  /// Wallhaven gives, so a test can exercise the not-found path without a
  /// separate flag.
  final Map<String, List<WallpaperCollection>> collections;

  /// The page each collection answers, keyed by [CollectionRef.key].
  final Map<String, WallpaperPage> collectionPages;

  /// Every [collectionPage] call, in order — so a test can assert the purity
  /// actually sent, which is the only filter that endpoint honours.
  final List<({CollectionRef collection, int page, PurityFilter purity})>
  collectionPageCalls =
      <({CollectionRef collection, int page, PurityFilter purity})>[];

  /// The page every [search] returns, unless [failure] is set.
  final WallpaperPage? page;

  /// Answers each [search] from the query itself rather than a fixed [page] —
  /// what a test reaches for when the *same* fake must answer differently
  /// before and after a filter changes, such as a tag going from allowed to
  /// blocked mid-test. Takes precedence over [page] when both are set.
  final WallpaperPage Function(SearchQuery query)? pageFor;

  /// Per-page-number responses, so pagination tests can serve a distinct page 2
  /// and assert on the query the grid built to reach it.
  final Map<int, WallpaperPage> pagesByNumber;

  /// The detail response returned for every wallpaper id.
  final WallpaperDetails? details;

  /// Optional per-id responses for gallery-selection tests.
  final Map<String, WallpaperDetails> detailsById;

  /// The account settings `GET /settings` answers with. Defaults to tela's own
  /// defaults, which is a *different* account from every test that sets this —
  /// so a test asserting that the account's defaults were adopted cannot pass
  /// by accident.
  final AccountSettings? account;

  /// When set, every call throws this instead of returning a page.
  final SourceFailure? failure;

  /// When set, only [wallpaperDetails] throws this — a source whose listings
  /// answer fine but which has no wallpaper under the id it was handed. What
  /// the id-jump chip's miss actually looks like.
  final SourceFailure? detailFailure;

  /// How long each [search] takes to answer, decided from the query itself.
  ///
  /// What a test reaches for when two searches must be in flight at once and
  /// the *order they land in* is the thing under test — a request the grid has
  /// already abandoned can still answer, and answer last.
  final Duration Function(SearchQuery query)? searchDelay;

  /// How this fake recognizes its own ids, for the browse id-jump chip.
  ///
  /// Defaults to recognizing nothing, so no existing test grows a chip it never
  /// asked for; a test that wants one supplies its own shape.
  final String? Function(String text) idIn;

  /// Every query passed to [search], oldest first.
  final List<SearchQuery> receivedQueries = <SearchQuery>[];

  /// Wallpaper ids requested for complete metadata, oldest first.
  final List<String> receivedDetailIds = <String>[];

  /// How many times [accountSettings] was called — the key check is one
  /// request, and it must stay one.
  int accountSettingsCalls = 0;

  @override
  Future<WallpaperPage> search(SearchQuery query) async {
    // Recorded when the request is *made*, not when it answers: a test
    // asserting on what was asked for must not depend on what answered first.
    receivedQueries.add(query);
    final Duration? delay = searchDelay?.call(query);
    if (delay != null) await Future<void>.delayed(delay);
    final SourceFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    final WallpaperPage Function(SearchQuery query)? answerWith = pageFor;
    if (answerWith != null) return answerWith(query);
    return pagesByNumber[query.page] ??
        page ??
        const WallpaperPage(
          wallpapers: <Wallpaper>[],
          hasMore: false,
          currentPage: 1,
          lastPage: 1,
        );
  }

  /// Tags this fake will report, keyed by id, and how many ids each call was
  /// asked for — so a test can prove a budget was honoured.
  Map<String, List<WallpaperTag>> tagsById = <String, List<WallpaperTag>>{};

  /// Every `tagsFor` call's budget, in order.
  final List<int> tagBudgets = <int>[];

  @override
  Future<Map<String, List<WallpaperTag>>> tagsFor(
    List<String> ids, {
    required int budget,
  }) async {
    tagBudgets.add(budget);
    return <String, List<WallpaperTag>>{
      for (final String id in ids.take(budget))
        if (tagsById[id] case final List<WallpaperTag> tags) id: tags,
    };
  }

  @override
  Future<WallpaperDetails> wallpaperDetails(String id) async {
    receivedDetailIds.add(id);
    final SourceFailure? toThrow = detailFailure ?? failure;
    if (toThrow != null) throw toThrow;
    final WallpaperDetails? result = detailsById[id] ?? details;
    if (result == null) {
      throw const UnexpectedResponseFailure('Fake has no detail response');
    }
    return result;
  }

  @override
  String? wallpaperIdIn(String text) => idIn(text);

  @override
  Future<List<WallpaperCollection>> collectionsOf(String username) async {
    final SourceFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    final List<WallpaperCollection>? owned = collections[username];
    if (owned == null) throw NotFoundFailure(username);
    return owned;
  }

  @override
  Future<WallpaperPage> collectionPage(
    CollectionRef collection, {
    required int page,
    required PurityFilter purity,
  }) async {
    collectionPageCalls.add((
      collection: collection,
      page: page,
      purity: purity,
    ));
    final SourceFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    final WallpaperPage? found = collectionPages[collection.key];
    if (found == null) throw NotFoundFailure(collection.key);
    return found;
  }

  @override
  Future<AccountSettings> accountSettings() async {
    accountSettingsCalls++;
    final SourceFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    return account ?? _telaDefaults;
  }

  /// The default [idIn]: a source that never offers an id jump.
  static String? _recognizesNothing(String text) => null;

  /// What an account that never changed a setting would answer with.
  static const AccountSettings _telaDefaults = AccountSettings(
    categories: CategoryFilter.all,
    topRange: TopRange.oneMonth,
  );
}

/// Everything Wallhaven supports — the default a fake wears.
const SourceCapabilities wallhavenLikeCapabilities = SourceCapabilities(
  filters: <SourceFilter>{
    SourceFilter.categories,
    SourceFilter.purity,
    SourceFilter.colors,
    SourceFilter.ratios,
    SourceFilter.resolutions,
    SourceFilter.tags,
    SourceFilter.order,
    SourceFilter.topRange,
  },
  sortings: <Sorting>{
    Sorting.dateAdded,
    Sorting.relevance,
    Sorting.random,
    Sorting.views,
    Sorting.favorites,
    Sorting.toplist,
    Sorting.hot,
  },
  purities: <Purity>{Purity.sfw, Purity.sketchy, Purity.nsfw},
  credentials: SourceCredentials.nsfwRequiresKey,
  requestsPerMinute: 45,
  syncsAccountDefaults: true,
  browsesCollections: true,
);

/// A deliberately *narrower* source: no categories, no colours, no toplist,
/// three sortings, and no credentials at all — the shape of a booru.
///
/// Named after nothing real on purpose. It exists so a test can prove the app
/// renders and guards from the capabilities rather than from Wallhaven's
/// habits, without waiting for the Konachan adapter to exist.
const SourceCapabilities narrowCapabilities = SourceCapabilities(
  filters: <SourceFilter>{
    SourceFilter.purity,
    SourceFilter.ratios,
    SourceFilter.resolutions,
    SourceFilter.tags,
  },
  sortings: <Sorting>{Sorting.dateAdded, Sorting.views, Sorting.favorites},
  purities: <Purity>{Purity.sfw, Purity.sketchy, Purity.nsfw},
  credentials: SourceCredentials.none,
  requestsPerMinute: 60,
  syncsAccountDefaults: false,
  browsesCollections: false,
);
