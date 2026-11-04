import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:tela/core/web/independent_steps.dart';
import 'package:tela/core/web/sign_in_browser.dart';
import 'package:tela/core/web/sign_in_browser_state.dart';
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
/// Holds the controller of the web view it built, so [retry] and
/// [forgetSession] reach it from the screen.
///
/// ```dart
/// final SignInBrowser browser = WebViewSignInBrowser();
/// ```
class WebViewSignInBrowser implements SignInBrowser {
  /// Creates the adapter. Its web view is made on the first [build].
  WebViewSignInBrowser();

  WebViewController? _controller;

  /// The page the last load started on, which [retry] goes back to.
  Uri _lastRequested = WallhavenSignIn.loginUrl;

  @override
  Widget build({
    required ValueChanged<String> onKeyFound,
    required ValueChanged<SignInBrowserState> onState,
  }) {
    final WebViewController controller = _controller ??= WebViewController();
    return _SignInWebView(
      controller: controller,
      onKeyFound: onKeyFound,
      onState: onState,
      onRequested: (Uri page) => _lastRequested = page,
      initialPage: _lastRequested,
    );
  }

  @override
  Future<void> retry() async {
    await _controller?.loadRequest(_lastRequested);
  }

  /// Each step is independent, so one failing does not leave the rest behind.
  @override
  Future<void> forgetSession() async {
    final WebViewController? controller = _controller;
    _controller = null;
    _lastRequested = WallhavenSignIn.loginUrl;
    await runIndependently(<Future<void> Function()>[
      WebViewCookieManager().clearCookies,
      if (controller != null) controller.clearCache,
      if (controller != null) controller.clearLocalStorage,
    ]);
  }
}

class _SignInWebView extends StatefulWidget {
  const _SignInWebView({
    required this.controller,
    required this.onKeyFound,
    required this.onState,
    required this.onRequested,
    required this.initialPage,
  });

  final WebViewController controller;
  final ValueChanged<String> onKeyFound;
  final ValueChanged<SignInBrowserState> onState;
  final ValueChanged<Uri> onRequested;
  final Uri initialPage;

  @override
  State<_SignInWebView> createState() => _SignInWebViewState();
}

class _SignInWebViewState extends State<_SignInWebView> {
  WebViewController get _controller => widget.controller;

  /// Android still fires `onPageFinished` for the error page it shows, and may
  /// deliver `onProgress` after it; the gate keeps both from undoing a
  /// settled state.
  final SignInStateGate _gate = SignInStateGate();

  @override
  void initState() {
    super.initState();
    unawaited(_configure());
  }

  Future<void> _configure() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: _gateTopFrame,
        onPageStarted: (String url) => _started(),
        onProgress: (int percent) => _emit(SignInLoading(percent / 100)),
        onWebResourceError: _onError,
        onPageFinished: (String url) => unawaited(_advance(url)),
      ),
    );
    _load(widget.initialPage);
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);

  void _load(Uri page) {
    widget.onRequested(page);
    unawaited(_controller.loadRequest(page));
  }

  void _emit(SignInBrowserState state) {
    final SignInBrowserState? shown = _gate.admit(state);
    if (!mounted || shown == null) return;
    widget.onState(shown);
  }

  void _started() {
    _gate.reset();
    _emit(const SignInLoading(0));
  }

  /// Sub-frame and sub-resource failures (an ad, a captcha beacon) are not the
  /// page failing, so only the top frame's count.
  void _onError(WebResourceError error) {
    if (error.isForMainFrame == false) return;
    _emit(const SignInFailed());
  }

  /// Keeps the top frame on wallhaven.cc. Sub-frames pass: a login captcha
  /// lives in one, served from its provider's own host.
  NavigationDecision _gateTopFrame(NavigationRequest request) {
    if (!request.isMainFrame) return NavigationDecision.navigate;
    final bool allowed = WallhavenSignIn.isWallhaven(Uri.parse(request.url));
    return allowed ? NavigationDecision.navigate : NavigationDecision.prevent;
  }

  Future<void> _advance(String url) async {
    if (_gate.failed) return;
    switch (WallhavenSignIn.stepFor(Uri.parse(url))) {
      case SignInStep.awaitCredentials:
        _emit(const SignInReady());
      case SignInStep.openAccountSettings:
        _load(WallhavenSignIn.accountSettingsUrl);
      case SignInStep.readKey:
        await _readKey();
    }
  }

  /// An account that never generated a key shows none: say so, and the user
  /// can create one on the page, which reloads it and brings us back here.
  Future<void> _readKey() async {
    final String? raw = await _runReadScript();
    if (raw == null || !mounted) return;
    final String? key = WallhavenSignIn.keyFrom(raw);
    if (key == null) return _emit(const SignInMissingKey());
    _emit(const SignInReady());
    widget.onKeyFound(key);
  }

  /// The script's result, or null if the page navigated away mid-call. That is
  /// not "no key": the next page's finish reads again, so nothing is emitted.
  Future<String?> _runReadScript() async {
    try {
      final Object raw = await _controller.runJavaScriptReturningResult(
        _readKeyScript,
      );
      return raw.toString();
    } on Object {
      return null;
    }
  }
}
