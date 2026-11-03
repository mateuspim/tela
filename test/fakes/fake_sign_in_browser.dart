import 'package:flutter/widgets.dart';
import 'package:tela/core/web/sign_in_browser.dart';

/// A [SignInBrowser] with no web view: a test plays the page by calling
/// [deliverKey], as the real one does once it reads Account settings.
class FakeSignInBrowser implements SignInBrowser {
  /// The callback the screen handed over in its latest [build].
  ValueChanged<String>? _onKeyFound;

  /// How many times the session was forgotten.
  int forgetCount = 0;

  @override
  Widget build({required ValueChanged<String> onKeyFound}) {
    _onKeyFound = onKeyFound;
    return const SizedBox(key: ValueKey<String>('fake-sign-in-browser'));
  }

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
}
