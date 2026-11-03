import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:tela/core/web/sign_in_browser.dart';
import 'package:tela/domain/models/wallhaven_sign_in.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Reads the key off Account settings. Prefers the named field, then falls back
/// to any input holding a 32-char alphanumeric value, so a renamed field does
/// not break the flow. The CSRF token is 40 chars and never matches.
const String _readKeyScript = r'''
(function () {
  var named = document.querySelector('input[name="api_key"], #api_key');
  if (named && named.value) return named.value.trim();
  var inputs = document.querySelectorAll('input');
  for (var i = 0; i < inputs.length; i++) {
    var value = (inputs[i].value || '').trim();
    if (/^[A-Za-z0-9]{32}$/.test(value)) return value;
  }
  return '';
})()
''';

/// [SignInBrowser] over the `webview_flutter` plugin.
///
/// ```dart
/// final SignInBrowser browser = const WebViewSignInBrowser();
/// ```
class WebViewSignInBrowser implements SignInBrowser {
  /// Creates the adapter. Each [build] gets its own web view.
  const WebViewSignInBrowser();

  @override
  Widget build({required ValueChanged<String> onKeyFound}) =>
      _SignInWebView(onKeyFound: onKeyFound);

  @override
  Future<void> forgetSession() => WebViewCookieManager().clearCookies();
}

class _SignInWebView extends StatefulWidget {
  const _SignInWebView({required this.onKeyFound});

  final ValueChanged<String> onKeyFound;

  @override
  State<_SignInWebView> createState() => _SignInWebViewState();
}

class _SignInWebViewState extends State<_SignInWebView> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: _gate,
        onPageFinished: (String url) => unawaited(_advance(url)),
      ),
    )
    ..loadRequest(WallhavenSignIn.loginUrl);

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);

  /// Keeps the top frame on wallhaven.cc. Sub-frames pass: a login captcha
  /// lives in one, served from its provider's own host.
  NavigationDecision _gate(NavigationRequest request) {
    if (!request.isMainFrame) return NavigationDecision.navigate;
    final bool allowed = WallhavenSignIn.isWallhaven(Uri.parse(request.url));
    return allowed ? NavigationDecision.navigate : NavigationDecision.prevent;
  }

  Future<void> _advance(String url) async {
    switch (WallhavenSignIn.stepFor(Uri.parse(url))) {
      case SignInStep.awaitCredentials:
        return;
      case SignInStep.openAccountSettings:
        await _controller.loadRequest(WallhavenSignIn.accountSettingsUrl);
      case SignInStep.readKey:
        await _readKey();
    }
  }

  /// An account that never generated a key shows none — the user can create
  /// one on the page, which reloads it and brings us back here.
  Future<void> _readKey() async {
    final Object raw = await _controller.runJavaScriptReturningResult(
      _readKeyScript,
    );
    final String? key = WallhavenSignIn.keyFrom(raw.toString());
    if (key == null || !mounted) return;
    widget.onKeyFound(key);
  }
}
