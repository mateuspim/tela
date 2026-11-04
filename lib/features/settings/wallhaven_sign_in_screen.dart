import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/web/sign_in_browser.dart';
import 'package:tela/core/web/sign_in_browser_state.dart';

/// Opens the Wallhaven sign-in screen. Returns the account's API key once it is
/// read off Account settings, or null if the user backs out first.
///
/// A pushed route rather than a go_router one: like the key dialog it replaces,
/// it is a sub-flow that hands a value back to its caller, not a destination.
///
/// On the root navigator: Settings lives in a shell branch, and a push onto the
/// branch's own navigator kept the Browse/Library/Settings bar showing under a
/// full-screen login (device pass, 2026-11-03).
///
/// ```dart
/// final String? key = await showWallhavenSignIn(context);
/// ```
Future<String?> showWallhavenSignIn(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<String>(
    MaterialPageRoute<String>(
      builder: (BuildContext context) => const WallhavenSignInScreen(),
    ),
  );
}

/// Wallhaven's own login page, embedded, with a line on what happens next.
///
/// The password goes into wallhaven.cc's form, never into tela. The session is
/// forgotten when this screen closes, harvested or not.
class WallhavenSignInScreen extends ConsumerStatefulWidget {
  /// Creates the sign-in screen.
  const WallhavenSignInScreen({super.key});

  @override
  ConsumerState<WallhavenSignInScreen> createState() =>
      _WallhavenSignInScreenState();
}

class _WallhavenSignInScreenState extends ConsumerState<WallhavenSignInScreen> {
  late final SignInBrowser _browser = ref.read(signInBrowserProvider);

  /// The page can report the key more than once (a reload, a regenerate), but
  /// the route may only be popped once.
  bool _done = false;

  SignInBrowserState _state = const SignInLoading(0);

  @override
  void dispose() {
    unawaited(_browser.forgetSession());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsSignInTitle),
        bottom: _progressBar(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _hint(context, l10n),
          Expanded(child: _page(l10n)),
        ],
      ),
    );
  }

  /// A hairline under the app bar while a page loads; nothing otherwise.
  PreferredSizeWidget? _progressBar() {
    final SignInBrowserState state = _state;
    if (state is! SignInLoading) return null;
    return PreferredSize(
      preferredSize: const Size.fromHeight(2),
      child: LinearProgressIndicator(
        key: const ValueKey<String>('sign-in-progress'),
        value: state.progress,
        minHeight: 2,
      ),
    );
  }

  /// The browser stays mounted under the error so a retry reloads in place.
  Widget _page(AppLocalizations l10n) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: _browser.build(onKeyFound: _finish, onState: _onState),
        ),
        if (_state is SignInFailed) Positioned.fill(child: _failure(l10n)),
      ],
    );
  }

  Widget _failure(AppLocalizations l10n) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(l10n.settingsSignInLoadFailed),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => unawaited(_browser.retry()),
              child: Text(l10n.settingsSignInRetry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hint(BuildContext context, AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);
    final bool missing = _state is SignInMissingKey;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Text(
        missing ? l10n.settingsSignInNoKeyHint : l10n.settingsSignInHint,
        style: theme.textTheme.bodySmall?.copyWith(
          color: missing
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  void _onState(SignInBrowserState state) {
    if (!mounted) return;
    setState(() => _state = state);
  }

  void _finish(String key) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(key);
  }
}
