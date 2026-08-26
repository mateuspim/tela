/// Why a call to a wallpaper source failed, in terms the UI can act on.
///
/// Dio, sockets, and HTTP status codes stop here: the data layer maps them to
/// one of these so no feature ever imports Dio to find out what went wrong.
/// Every source's adapter raises these same four, so a screen's error handling
/// does not learn which site it was talking to.
sealed class SourceFailure implements Exception {
  /// Creates a failure with a developer-facing [message].
  const SourceFailure(this.message);

  /// Developer-facing detail. Never shown raw to users — features map these
  /// to localized strings — and never contains an API key.
  final String message;

  /// Stable name for logs. Not `runtimeType`, which minification rewrites.
  String get kind;

  @override
  String toString() => '$kind: $message';
}

/// The API key is missing, malformed, or rejected (HTTP 401).
///
/// Also what you get for asking for NSFW purity with no key at all, on a
/// source that requires one.
class InvalidApiKeyFailure extends SourceFailure {
  /// Creates an invalid-key failure.
  const InvalidApiKeyFailure([super.message = 'the source rejected the key']);

  @override
  String get kind => 'invalid_api_key';
}

/// The user's own collections were asked for without tela knowing which
/// account is theirs.
///
/// Its own case rather than a [NotFoundFailure] because the remedy is
/// different — type a username into Settings, not "no such account" — and the
/// source cannot tell the two apart on tela's behalf: Wallhaven answers an
/// unknown username, an account with nothing public, and a keyless read with
/// the same 404 body (measured live 2026-08-26). The distinction only exists
/// on this side of the call, so it is drawn before the call.
class NoCollectionsUsernameFailure extends SourceFailure {
  /// Creates the failure.
  const NoCollectionsUsernameFailure([
    super.message = 'no collections username is stored for this source',
  ]);

  @override
  String get kind => 'no_collections_username';
}

/// The source's request ceiling was hit (HTTP 429).
///
/// [retryAfter] is the server's hint when it sends one; the client backs off
/// exponentially rather than trusting it blindly. The ceiling itself is
/// per-source — Wallhaven's is 45/min — so the message carries it rather than
/// this class naming one.
class RateLimitedFailure extends SourceFailure {
  /// Creates a rate-limit failure.
  const RateLimitedFailure({
    this.retryAfter,
    String message = 'the source rate limit was reached',
  }) : super(message);

  /// How long the server asked us to wait, if it said.
  final Duration? retryAfter;

  @override
  String get kind => 'rate_limited';
}

/// The device could not reach the source — no network, DNS, TLS, or timeout.
class NetworkFailure extends SourceFailure {
  /// Creates a network failure.
  const NetworkFailure([super.message = 'could not reach the source']);

  @override
  String get kind => 'network';
}

/// The source answered clearly that it has no wallpaper with that id.
///
/// Distinct from [UnexpectedResponseFailure] because it is not a malfunction:
/// it is the expected answer to a mistyped id, or to an id belonging to a
/// different site. Carrying the [id] lets the message name it instead of
/// telling someone who typed six characters that something went wrong.
class NotFoundFailure extends SourceFailure {
  /// Creates a not-found failure for the looked-up [id].
  NotFoundFailure(this.id) : super('no wallpaper "$id" at the source');

  /// The id that found nothing, as it went out on the wire.
  final String id;

  @override
  String get kind => 'not_found';
}

/// The source answered, but not with anything we can parse.
///
/// Wallhaven's ToS reserves the right to change the API without notice and a
/// booru has no versioned API at all, so this is a real runtime case, not a
/// "can't happen" — fail soft, don't crash the grid.
class UnexpectedResponseFailure extends SourceFailure {
  /// Creates a malformed-response failure.
  const UnexpectedResponseFailure(super.message);

  @override
  String get kind => 'unexpected_response';
}
