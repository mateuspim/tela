import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_capabilities.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper_collection.dart';
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

  /// The tags each of [ids] carries, for as many as [budget] allows.
  ///
  /// Feeds the tag chooser, which offers the tags a *selection* has in common —
  /// so this is asked about ten or twenty wallpapers at once, not one.
  ///
  /// **The cost is wildly different per source, and that is why there is a
  /// budget rather than a loop over [wallpaperDetails].** A booru returns every
  /// post's tags in the listing that drew the grid, so it can answer a visible
  /// selection for free. Wallhaven's `/search` carries no tags at all — they
  /// exist only on `/w/{id}` — so every id there is a request against a
  /// 45/minute ceiling that the downloads themselves are about to need.
  ///
  /// [budget] caps how many **requests** this may spend, not how many ids it
  /// may answer: ids the source already knows cost nothing and are always
  /// included. Ids beyond the budget are simply absent from the result — a
  /// partial answer is the expected outcome for a large selection, not a
  /// failure, and the chooser shows what arrived.
  ///
  /// Answers an empty map rather than throwing when the source cannot be
  /// reached: a tag suggestion is a convenience, and losing it must never cost
  /// the download the user actually asked for.
  ///
  /// ```dart
  /// final Map<String, List<WallpaperTag>> tags =
  ///     await source.tagsFor(<String>['e7jvjd'], budget: 25);
  /// ```
  Future<Map<String, List<WallpaperTag>>> tagsFor(
    List<String> ids, {
    required int budget,
  });

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

  /// The collections [username] publishes.
  ///
  /// Only meaningful where [SourceCapabilities.browsesCollections] is true; a
  /// source without collections throws [UnsupportedError], the same contract
  /// [accountSettings] has for a source without accounts.
  ///
  /// **Always addressed by username, including your own** — there is no
  /// "mine" route worth having. Wallhaven does publish a bare `/collections`
  /// for the authenticated user, but neither it nor `/settings` returns the
  /// username (confirmed against the published API reference, 2026-08-26), and
  /// the contents endpoint is addressed as `/collections/{username}/{id}` — so
  /// that route hands back ids it gives you no way to open. Asking by name
  /// instead costs one stored setting and answers both cases with one request:
  /// a stranger's public lists keylessly, and *all* of your own, private ones
  /// included, once the stored key makes it your account being read.
  ///
  /// Throws [NotFoundFailure] naming [username] when the source has no such
  /// account, and the same safe failures as [search] otherwise.
  ///
  /// ```dart
  /// final List<WallpaperCollection> theirs =
  ///     await source.collectionsOf('jrmnt');
  /// ```
  Future<List<WallpaperCollection>> collectionsOf(String username);

  /// Fetches one page of the wallpapers inside [collection].
  ///
  /// **[purity] is the only filter this honours, and the rest are not merely
  /// ignored — they are silently ignored**, which is the failure mode
  /// [SourceFilter] exists to design out. Measured live on 2026-08-26 against
  /// Wallhaven collection `jrmnt/585550` (447 wallpapers): `categories`,
  /// `atleast`, `ratios`, `sorting` and `order` each left the total at 447 and
  /// the order untouched. A collection is a hand-ordered list, so its order is
  /// its own and there is nothing to sort by. Callers must therefore offer
  /// purity alone — see `CollectionListingScreen`.
  ///
  /// Throws [NotFoundFailure] naming the collection when the source has no such
  /// list, and the same safe failures as [search] otherwise.
  Future<WallpaperPage> collectionPage(
    CollectionRef collection, {
    required int page,
    required PurityFilter purity,
  });

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
