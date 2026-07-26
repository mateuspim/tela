import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_capabilities.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';

/// One site tela can browse — the only way the app talks to any of them.
///
/// Owned by the domain, implemented once per site in `data/<source>/`.
/// Features depend on this and never on the HTTP client, so replacing Dio —
/// or adding a second site — touches one adapter. Implementations throw
/// [SourceFailure], never a transport exception.
///
/// ```dart
/// final WallpaperPage page = await source.search(const SearchQuery());
/// ```
abstract interface class WallpaperSource {
  /// Which site this is. Every wallpaper it returns carries the same id, and
  /// it is half of every stored row's key.
  SourceId get id;

  /// The site's own name, as it writes it — "Wallhaven", "Konachan".
  ///
  /// Not localized, and deliberately: these are proper nouns, and a brand does
  /// not translate. The l10n string is the sentence *around* it.
  String get displayName;

  /// What this site can actually be asked for. The filter sheet renders from
  /// it, and the search use case reads it instead of assuming Wallhaven's
  /// rules.
  SourceCapabilities get capabilities;

  /// Fetches one page of listings for [query].
  ///
  /// Throws [InvalidApiKeyFailure] if [query] asks for something this source
  /// serves only to a key it has not got, [RateLimitedFailure] once its own
  /// ceiling is hit, [NetworkFailure] when it is unreachable, and
  /// [UnexpectedResponseFailure] if the payload doesn't parse.
  Future<WallpaperPage> search(SearchQuery query);

  /// Fetches complete metadata for a single wallpaper [id] of *this* source.
  ///
  /// Throws the same safe failures as [search], plus [NotFoundFailure] when the
  /// source answers clearly that it has no such wallpaper.
  Future<WallpaperDetails> wallpaperDetails(String id);

  /// The source-native wallpaper id inside [text], or null if it isn't one.
  ///
  /// Id shape is site-specific — Wallhaven's is six characters of its own
  /// alphabet, Konachan's is a decimal post number — so only the source can
  /// judge it, and a source that cannot recognise its own ids just answers
  /// null. Normalizing is *part* of recognizing: Wallhaven's API is
  /// case-sensitive and its ids are lowercase, so a phone keyboard's
  /// auto-capitalized `Je9ldp` has to come back as `je9ldp` or the lookup that
  /// follows 404s. Returning the normalized id rather than a bool is what makes
  /// that impossible to forget at the call site.
  ///
  /// Only ever decides whether to *offer* a jump — the id itself is confirmed
  /// against the live API by [wallpaperDetails], never by this pattern.
  ///
  /// ```dart
  /// final String? id = source.wallpaperIdIn(' Je9ldp '); // 'je9ldp'
  /// ```
  String? wallpaperIdIn(String text);

  /// Fetches the browse defaults of the account the stored key belongs to.
  ///
  /// Only meaningful where [SourceCapabilities.syncsAccountDefaults] is true.
  /// On Wallhaven this is `GET /settings`, which serves nobody without a key —
  /// so it is also the request that tells a good key from a bad one, and
  /// `SaveApiKey` uses it as exactly that. Throws [InvalidApiKeyFailure] when
  /// the key is missing or rejected, and the same safe failures as [search]
  /// otherwise. A source with no accounts throws [UnsupportedError]: reaching
  /// it without asking the capability first is a programming error, not a
  /// runtime one.
  Future<AccountSettings> accountSettings();
}
