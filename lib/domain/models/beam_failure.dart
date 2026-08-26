/// Why a beam could not be completed, in terms the UI can act on.
///
/// Sockets, TLS and HTTP status codes stop at the adapter: it maps them to one
/// of these so no feature imports Dio to find out what went wrong — the same
/// contract `SourceFailure` has for a wallpaper source.
sealed class BeamFailure implements Exception {
  /// Creates a failure with a developer-facing [message].
  const BeamFailure(this.message);

  /// Developer-facing detail. Never shown raw to users, and **never contains a
  /// file path** — a beamed explicit file's path is exactly what CLAUDE.md's
  /// logging rule forbids recording.
  final String message;

  /// Stable name for logs. Not `runtimeType`, which minification rewrites.
  String get kind;

  @override
  String toString() => '$kind: $message';
}

/// The receiver could not be reached at all.
class BeamUnreachableFailure extends BeamFailure {
  /// Creates an unreachable failure.
  const BeamUnreachableFailure([
    super.message = 'the receiver did not answer',
  ]);

  @override
  String get kind => 'beam_unreachable';
}

/// The receiver declined the transfer.
///
/// The ordinary, expected outcome of someone tapping "decline" on their
/// desktop, which is why it is not an error to apologise for. LocalSend
/// answers 403 for it.
class BeamDeclinedFailure extends BeamFailure {
  /// Creates a declined failure.
  const BeamDeclinedFailure([super.message = 'the receiver declined']);

  @override
  String get kind => 'beam_declined';
}

/// The receiver wants a PIN tela was not given, or was given the wrong one.
class BeamPinRequiredFailure extends BeamFailure {
  /// Creates a PIN failure.
  const BeamPinRequiredFailure([super.message = 'the receiver wants a PIN']);

  @override
  String get kind => 'beam_pin_required';
}

/// The receiver is already busy with another transfer (HTTP 409).
class BeamBusyFailure extends BeamFailure {
  /// Creates a busy failure.
  const BeamBusyFailure([super.message = 'the receiver is already receiving']);

  @override
  String get kind => 'beam_busy';
}

/// Explicit content was queued while the opt-in beam setting is off.
///
/// Raised by the use case before anything leaves the device, and it is the
/// enforcement half of `mayBeamBitmap` — the UI withholds the action too, the
/// same belt-and-braces every NSFW rule in tela gets.
class BeamExplicitRefusedFailure extends BeamFailure {
  /// Creates the refusal.
  const BeamExplicitRefusedFailure([
    super.message =
        'explicit wallpapers may only be beamed once the setting is on',
  ]);

  @override
  String get kind => 'beam_explicit_refused';
}

/// The receiver answered in a way this protocol version does not describe.
class BeamUnexpectedFailure extends BeamFailure {
  /// Creates an unexpected-response failure.
  const BeamUnexpectedFailure(super.message);

  @override
  String get kind => 'beam_unexpected';
}
