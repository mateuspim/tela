import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
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
  FakeWallhavenApi({this.page, this.details, this.account, this.failure});

  /// The page every [search] returns, unless [failure] is set.
  final WallpaperPage? page;

  /// The detail response returned for every wallpaper id.
  final WallpaperDetails? details;

  /// The account settings `GET /settings` answers with. Defaults to tela's own
  /// defaults, which is a *different* account from every test that sets this —
  /// so a test asserting that the account's defaults were adopted cannot pass
  /// by accident.
  final AccountSettings? account;

  /// When set, every call throws this instead of returning a page.
  final WallhavenFailure? failure;

  /// Every query passed to [search], oldest first.
  final List<SearchQuery> receivedQueries = <SearchQuery>[];

  /// How many times [accountSettings] was called — the key check is one
  /// request, and it must stay one.
  int accountSettingsCalls = 0;

  @override
  Future<WallpaperPage> search(SearchQuery query) async {
    receivedQueries.add(query);
    final WallhavenFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    return page ??
        const WallpaperPage(
          wallpapers: <Wallpaper>[],
          currentPage: 1,
          lastPage: 1,
        );
  }

  @override
  Future<WallpaperDetails> wallpaperDetails(String id) async {
    final WallhavenFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    final WallpaperDetails? result = details;
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
    purity: PurityFilter.sfwOnly,
    topRange: TopRange.oneMonth,
  );
}
