import 'package:flutter/widgets.dart';
import 'package:tela/core/web/sign_in_browser.dart';
import 'package:tela/core/web/sign_in_browser_state.dart';

/// A [SignInBrowser] with no web view: a test plays the page by calling
/// [deliverKey] and [deliverState], as the real one does while it loads.
class FakeSignInBrowser implements SignInBrowser {
  /// The callbacks the screen handed over in its latest [build].
  ValueChanged<String>? _onKeyFound;
  ValueChanged<SignInBrowserState>? _onState;

  /// How many times the session was forgotten.
  int forgetCount = 0;

  /// How many times the failed page was retried.
  int retryCount = 0;

  @override
  Widget build({
    required ValueChanged<String> onKeyFound,
    required ValueChanged<SignInBrowserState> onState,
  }) {
    _onKeyFound = onKeyFound;
    _onState = onState;
    return const SizedBox(key: ValueKey<String>('fake-sign-in-browser'));
  }

  @override
  Future<void> retry() async => retryCount++;

  @override
  Future<void> forgetSession() async => forgetCount++;

  /// Reports [key] as read off the page.
  void deliverKey(String key) {
    final ValueChanged<String>? onKeyFound = _onKeyFound;
    if (onKeyFound == null) {
      throw StateError('deliverKey needs a built browser, got none');
    }
    onKeyFound(key);
  }

  /// Reports [state] as what the page is now doing.
  void deliverState(SignInBrowserState state) {
    final ValueChanged<SignInBrowserState>? onState = _onState;
    if (onState == null) {
      throw StateError('deliverState needs a built browser, got none');
    }
    onState(state);
  }
}
