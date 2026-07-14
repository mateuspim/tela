import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';

/// The only way the app talks to Wallhaven.
///
/// Owned by the domain, implemented in `data/` over Dio. Features depend on
/// this and never on the HTTP client, so replacing Dio touches one adapter.
/// Implementations throw [WallhavenFailure], never a transport exception.
///
/// ```dart
/// final WallpaperPage page = await api.search(const SearchQuery());
/// ```
abstract interface class WallhavenApi {
  /// Fetches one page of listings for [query].
  ///
  /// Throws [InvalidApiKeyFailure] if [query] asks for NSFW without a valid
  /// key, [RateLimitedFailure] once the 45 req/min ceiling is hit,
  /// [NetworkFailure] when Wallhaven is unreachable, and
  /// [UnexpectedResponseFailure] if the payload doesn't parse.
  Future<WallpaperPage> search(SearchQuery query);

  /// Fetches complete metadata for a single Wallhaven wallpaper [id].
  ///
  /// Uses `GET /w/{id}` and throws the same safe failures as [search].
  Future<WallpaperDetails> wallpaperDetails(String id);

  /// Fetches the browse defaults of the account the stored key belongs to.
  ///
  /// Uses `GET /settings`, which serves nobody without a key — so this is also
  /// the request that tells a good key from a bad one, and `SaveApiKey` uses it
  /// as exactly that. Throws [InvalidApiKeyFailure] when the key is missing or
  /// rejected, and the same safe failures as [search] otherwise.
  Future<AccountSettings> accountSettings();
}
