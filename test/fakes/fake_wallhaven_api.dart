import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/ports/wallhaven_api.dart';

/// In-memory [WallhavenApi] that records what it was asked for.
///
/// Records every [SearchQuery] it receives so tests can assert on the request
/// the use case *built*, which is where the seed and paging bugs live.
class FakeWallhavenApi implements WallhavenApi {
  /// Creates a fake that answers every search with [page], or throws [failure].
  FakeWallhavenApi({
    this.page,
    this.pagesByNumber = const <int, WallpaperPage>{},
    this.details,
    this.detailsById = const <String, WallpaperDetails>{},
    this.account,
    this.failure,
  });

  /// The page every [search] returns, unless [failure] is set.
  final WallpaperPage? page;

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
  final WallhavenFailure? failure;

  /// Every query passed to [search], oldest first.
  final List<SearchQuery> receivedQueries = <SearchQuery>[];

  /// Wallpaper ids requested for complete metadata, oldest first.
  final List<String> receivedDetailIds = <String>[];

  /// How many times [accountSettings] was called — the key check is one
  /// request, and it must stay one.
  int accountSettingsCalls = 0;

  @override
  Future<WallpaperPage> search(SearchQuery query) async {
    receivedQueries.add(query);
    final WallhavenFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    return pagesByNumber[query.page] ??
        page ??
        const WallpaperPage(
          wallpapers: <Wallpaper>[],
          currentPage: 1,
          lastPage: 1,
        );
  }

  @override
  Future<WallpaperDetails> wallpaperDetails(String id) async {
    receivedDetailIds.add(id);
    final WallhavenFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    final WallpaperDetails? result = detailsById[id] ?? details;
    if (result == null) {
      throw const UnexpectedResponseFailure('Fake has no detail response');
    }
    return result;
  }

  @override
  Future<AccountSettings> accountSettings() async {
    accountSettingsCalls++;
    final WallhavenFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    return account ?? _telaDefaults;
  }

  /// What an account that never changed a setting would answer with.
  static const AccountSettings _telaDefaults = AccountSettings(
    categories: CategoryFilter.all,
    topRange: TopRange.oneMonth,
  );
}
