/// What the embedded sign-in page should do next, given where it just landed.
enum SignInStep {
  /// The user is still on a login, sign-up, or password page. Leave them be.
  awaitCredentials,

  /// Signed in and somewhere else on Wallhaven: go to Account settings, where
  /// the key lives.
  openAccountSettings,

  /// On Account settings: read the key off the page.
  readKey,
}

/// The rules of the "sign in to fetch your API key" flow, as plain Dart.
///
/// Wallhaven's API has no login endpoint — a key is only ever shown on the
/// website's Account settings page, behind a browser session. So the flow runs
/// the user through wallhaven.cc's own login in a web view and reads the key
/// once it is on screen. tela never sees the password: it is typed into
/// Wallhaven's page, not ours. Only the decisions live here, so they test
/// without a web view.
///
/// ```dart
/// if (WallhavenSignIn.stepFor(Uri.parse(url)) == SignInStep.readKey) { ... }
/// ```
abstract final class WallhavenSignIn {
  /// Where the flow starts.
  static final Uri loginUrl = Uri.parse('https://wallhaven.cc/login');

  /// The page that shows the account's API key.
  static final Uri accountSettingsUrl = Uri.parse(
    'https://wallhaven.cc/settings/account',
  );

  /// Path prefixes of pages that are part of signing in, not past it.
  static const List<String> _credentialPaths = <String>[
    '/login',
    '/register',
    '/password',
    '/auth',
    '/verify',
  ];

  /// A Wallhaven key as the account page shows it: 32 letters and digits.
  ///
  /// Strict on purpose — the page also carries Laravel's 40-char CSRF token,
  /// and that must never be mistaken for the key. `SaveApiKey` still verifies
  /// whatever passes here against the API.
  static final RegExp _keyShape = RegExp(r'^[A-Za-z0-9]{32}$');

  /// The step for a page that finished loading at [page].
  static SignInStep stepFor(Uri page) {
    if (!isWallhaven(page)) return SignInStep.awaitCredentials;
    if (page.path == accountSettingsUrl.path) return SignInStep.readKey;
    final bool signingIn = _credentialPaths.any(page.path.startsWith);
    if (signingIn) return SignInStep.awaitCredentials;
    return SignInStep.openAccountSettings;
  }

  /// Whether [page] is wallhaven.cc over https — the only place the sign-in
  /// view may go. Anything else would be a browser tela never meant to ship.
  static bool isWallhaven(Uri page) {
    if (page.scheme != 'https') return false;
    return page.host == 'wallhaven.cc' || page.host == 'www.wallhaven.cc';
  }

  /// The key in [raw], what the page script returned, or null if none.
  ///
  /// Android's web view hands a JS string back JSON-quoted (`"abc"`), so one
  /// pair of surrounding quotes is dropped before the shape check.
  static String? keyFrom(String raw) {
    final String unquoted = _unquote(raw.trim());
    return _keyShape.hasMatch(unquoted) ? unquoted : null;
  }

  static String _unquote(String text) {
    final bool quoted =
        text.length >= 2 && text.startsWith('"') && text.endsWith('"');
    return quoted ? text.substring(1, text.length - 1) : text;
  }
}
