import 'package:flutter/widgets.dart';

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
  /// time it reads a key off Account settings.
  Widget build({required ValueChanged<String> onKeyFound});

  /// Drops the web session's cookies, so tela keeps the key and nothing else:
  /// no logged-in Wallhaven session is left behind in the app.
  Future<void> forgetSession();
}
