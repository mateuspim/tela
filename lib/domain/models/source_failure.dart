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
