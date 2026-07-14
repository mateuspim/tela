/// Why a Wallhaven call failed, in terms the UI can act on.
///
/// Dio, sockets, and HTTP status codes stop here: the data layer maps them to
/// one of these so no feature ever imports Dio to find out what went wrong.
sealed class WallhavenFailure implements Exception {
  /// Creates a failure with a developer-facing [message].
  const WallhavenFailure(this.message);

  /// Developer-facing detail. Never shown raw to users — features map these
  /// to localized strings — and never contains the API key.
  final String message;

  /// Stable name for logs. Not `runtimeType`, which minification rewrites.
  String get kind;

  @override
  String toString() => '$kind: $message';
}

/// The API key is missing, malformed, or rejected (HTTP 401).
///
/// Also what you get for asking for NSFW purity with no key at all.
class InvalidApiKeyFailure extends WallhavenFailure {
  /// Creates an invalid-key failure.
  const InvalidApiKeyFailure([
    super.message = 'Wallhaven rejected the API key',
  ]);

  @override
  String get kind => 'invalid_api_key';
}

/// The 45 req/min ceiling was hit (HTTP 429).
///
/// [retryAfter] is Wallhaven's hint when it sends one; the client backs off
/// exponentially rather than trusting it blindly.
class RateLimitedFailure extends WallhavenFailure {
  /// Creates a rate-limit failure.
  const RateLimitedFailure({this.retryAfter})
    : super('Wallhaven rate limit reached (45 req/min)');

  /// How long the server asked us to wait, if it said.
  final Duration? retryAfter;

  @override
  String get kind => 'rate_limited';
}

/// The device could not reach Wallhaven — no network, DNS, TLS, or timeout.
class NetworkFailure extends WallhavenFailure {
  /// Creates a network failure.
  const NetworkFailure([super.message = 'Could not reach Wallhaven']);

  @override
  String get kind => 'network';
}

/// Wallhaven answered, but not with anything we can parse.
///
/// The ToS reserves the right to change the API without notice, so this is a
/// real runtime case, not a "can't happen" — fail soft, don't crash the grid.
class UnexpectedResponseFailure extends WallhavenFailure {
  /// Creates a malformed-response failure.
  const UnexpectedResponseFailure(super.message);

  @override
  String get kind => 'unexpected_response';
}
