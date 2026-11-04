/// What the embedded sign-in browser is doing, as the screen needs to show it.
///
/// Sealed so the screen's `switch` covers every case; the plugin's own
/// callbacks (page started, progress, resource error) stay inside the adapter.
///
/// ```dart
/// final bool busy = state is SignInLoading;
/// ```
sealed class SignInBrowserState {
  const SignInBrowserState();
}

/// A page is loading. [progress] runs 0.0 to 1.0.
final class SignInLoading extends SignInBrowserState {
  /// Creates the loading state at [progress].
  const SignInLoading(this.progress);

  /// How much of the page has arrived, 0.0 to 1.0.
  final double progress;
}

/// The page is up and the user can use it.
final class SignInReady extends SignInBrowserState {
  /// Creates the ready state.
  const SignInReady();
}

/// The top frame failed to load (offline, wallhaven.cc down). Retry reloads.
final class SignInFailed extends SignInBrowserState {
  /// Creates the failed state.
  const SignInFailed();
}

/// The user is on Account settings but the page shows no API key, because
/// the account never generated one. Creating a key reloads the page, which
/// reads it.
final class SignInMissingKey extends SignInBrowserState {
  /// Creates the missing-key state.
  const SignInMissingKey();
}

/// Decides which reported states reach the screen, so a late progress tick
/// cannot undo a settled one.
///
/// Android does not order `onProgress` against `onPageFinished`: a tick can
/// land after the page finished and would flip Ready (or MissingKey) back to
/// Loading, leaving a full bar stuck. Once a state settles — ready, failed or
/// missing key — loading ticks are dropped until [reset] (a new page started).
///
/// ```dart
/// final SignInBrowserState? shown = gate.admit(const SignInLoading(0.9));
/// ```
class SignInStateGate {
  bool _settled = false;
  bool _failed = false;

  /// Whether the last admitted state was [SignInFailed].
  bool get failed => _failed;

  /// Forgets the settled state: a new page started loading.
  void reset() {
    _settled = false;
    _failed = false;
  }

  /// [state] if it should be shown, or null if it is a stale loading tick.
  SignInBrowserState? admit(SignInBrowserState state) {
    if (state is SignInLoading && _settled) return null;
    _settled = state is! SignInLoading;
    _failed = state is SignInFailed;
    return state;
  }
}
