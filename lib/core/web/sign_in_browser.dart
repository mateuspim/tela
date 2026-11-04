import 'package:flutter/widgets.dart';
import 'package:tela/core/web/sign_in_browser_state.dart';

/// The embedded browser the "sign in to Wallhaven" screen shows.
///
/// A port like the ones in `domain/ports`, but it lives in `core` because what
/// it hands back is a widget, and the domain stays free of Flutter. Its
/// decisions (where to go, what counts as a key) are already pure Dart in
/// `WallhavenSignIn`; this only wraps the `webview_flutter` plugin, so a
/// feature never imports it and a test swaps in a fake.
///
/// ```dart
/// browser.build(onKeyFound: (String key) => Navigator.pop(context, key));
/// ```
abstract interface class SignInBrowser {
  /// The web view, already on Wallhaven's login page. Calls [onKeyFound] each
  /// time it reads a key off Account settings, and [onState] whenever what it
  /// is doing changes (loading, ready, failed, no key on the account).
  Widget build({
    required ValueChanged<String> onKeyFound,
    required ValueChanged<SignInBrowserState> onState,
  });

  /// Loads again the page that failed. Meant for the [SignInFailed] state.
  Future<void> retry();

  /// Drops everything the web session left: cookies, cache and local storage,
  /// so tela keeps the key and nothing else — no logged-in Wallhaven session
  /// is left behind in the app.
  Future<void> forgetSession();
}
