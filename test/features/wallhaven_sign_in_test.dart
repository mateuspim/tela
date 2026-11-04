import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/web/sign_in_browser_state.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/features/settings/api_key_section.dart';
import 'package:tela/features/settings/wallhaven_sign_in_screen.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_sign_in_browser.dart';
import '../fakes/fake_wallpaper_source.dart';

const String _key = 'AbCdEfGhIjKlMnOpQrStUvWxYz012345';

void main() {
  testWidgets('offers sign-in only while no key is stored', (
    WidgetTester tester,
  ) async {
    await _pumpSection(tester, secrets: FakeSecretStore(storedKey: _key));

    expect(find.text('Sign in to Wallhaven'), findsNothing);
  });

  testWidgets('saves the key the sign-in page found, then forgets the '
      'session', (WidgetTester tester) async {
    final FakeSecretStore secrets = FakeSecretStore();
    final FakeSignInBrowser browser = FakeSignInBrowser();
    await _pumpSection(tester, secrets: secrets, browser: browser);

    await _openSignIn(tester);
    browser.deliverKey(_key);
    await tester.pumpAndSettle();

    expect(find.byType(WallhavenSignInScreen), findsNothing);
    expect(secrets.storedKey, _key);
    expect(find.text('API key saved.'), findsOneWidget);
    expect(browser.forgetCount, 1);
  });

  testWidgets('covers the whole app, not just the Settings tab', (
    WidgetTester tester,
  ) async {
    // Settings sits in a shell branch with its own navigator; pushing there
    // left the bottom bar showing under the login (device pass, 2026-11-03).
    await _pumpSection(tester, nested: true);

    await _openSignIn(tester);

    final NavigatorState root = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    final NavigatorState host = Navigator.of(
      tester.element(find.byType(WallhavenSignInScreen)),
    );
    expect(host, same(root));
  });

  testWidgets('a key reported twice pops the screen once', (
    WidgetTester tester,
  ) async {
    final FakeSignInBrowser browser = FakeSignInBrowser();
    await _pumpSection(tester, browser: browser);

    await _openSignIn(tester);
    browser
      ..deliverKey(_key)
      ..deliverKey(_key);
    await tester.pumpAndSettle();

    // A second pop would have taken the section's own route with it.
    expect(find.byType(ApiKeySection), findsOneWidget);
  });

  testWidgets('backing out stores nothing and still forgets the session', (
    WidgetTester tester,
  ) async {
    final FakeSecretStore secrets = FakeSecretStore();
    final FakeSignInBrowser browser = FakeSignInBrowser();
    await _pumpSection(tester, secrets: secrets, browser: browser);

    await _openSignIn(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(secrets.storedKey, isNull);
    expect(browser.forgetCount, 1);
  });

  testWidgets('a harvested key Wallhaven rejects is not kept', (
    WidgetTester tester,
  ) async {
    final FakeSecretStore secrets = FakeSecretStore();
    final FakeSignInBrowser browser = FakeSignInBrowser();
    await _pumpSection(
      tester,
      secrets: secrets,
      browser: browser,
      source: FakeWallpaperSource(failure: const InvalidApiKeyFailure()),
    );

    await _openSignIn(tester);
    browser.deliverKey(_key);
    await tester.pumpAndSettle();

    expect(secrets.storedKey, isNull);
    expect(find.text('That Wallhaven API key was rejected.'), findsOneWidget);
  });

  testWidgets('shows a progress bar while loading and drops it when ready', (
    WidgetTester tester,
  ) async {
    final FakeSignInBrowser browser = FakeSignInBrowser();
    await _pumpSection(tester, browser: browser);
    await _openSignIn(tester);
    const Key bar = ValueKey<String>('sign-in-progress');
    expect(find.byKey(bar), findsOneWidget);

    browser.deliverState(const SignInLoading(0.5));
    await tester.pump();
    expect(tester.widget<LinearProgressIndicator>(find.byKey(bar)).value, 0.5);

    browser.deliverState(const SignInReady());
    await tester.pump();
    expect(find.byKey(bar), findsNothing);
  });

  testWidgets('a failed load shows the error, and Retry reloads it', (
    WidgetTester tester,
  ) async {
    final FakeSignInBrowser browser = FakeSignInBrowser();
    await _pumpSection(tester, browser: browser);
    await _openSignIn(tester);

    browser.deliverState(const SignInFailed());
    await tester.pump();
    expect(find.textContaining("Couldn't load Wallhaven"), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(browser.retryCount, 1);

    browser.deliverState(const SignInLoading(0));
    await tester.pump();
    expect(find.textContaining("Couldn't load Wallhaven"), findsNothing);
  });

  testWidgets('an account with no key is told to generate one', (
    WidgetTester tester,
  ) async {
    final FakeSignInBrowser browser = FakeSignInBrowser();
    await _pumpSection(tester, browser: browser);
    await _openSignIn(tester);
    expect(find.textContaining('No API key on this account'), findsNothing);

    browser.deliverState(const SignInMissingKey());
    await tester.pump();
    expect(find.textContaining('No API key on this account'), findsOneWidget);

    browser.deliverState(const SignInLoading(0));
    await tester.pump();
    expect(find.textContaining('No API key on this account'), findsNothing);
  });
}

Future<void> _openSignIn(WidgetTester tester) async {
  await tester.tap(find.text('Sign in to Wallhaven'));
  await tester.pumpAndSettle();
  expect(find.byType(WallhavenSignInScreen), findsOneWidget);
}

Future<void> _pumpSection(
  WidgetTester tester, {
  FakeSecretStore? secrets,
  FakeSignInBrowser? browser,
  FakeWallpaperSource? source,
  bool nested = false,
}) async {
  const Widget section = Scaffold(body: ApiKeySection());
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        secretStoreProvider.overrideWithValue(secrets ?? FakeSecretStore()),
        wallhavenSourceProvider.overrideWithValue(
          source ?? FakeWallpaperSource(),
        ),
        signInBrowserProvider.overrideWithValue(browser ?? FakeSignInBrowser()),
      ],
      child: MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        // `nested` stands in for go_router's shell branch: the section under
        // a navigator of its own, below the app's root one.
        home: nested
            ? Navigator(
                onGenerateRoute: (RouteSettings _) => MaterialPageRoute<void>(
                  builder: (BuildContext _) => section,
                ),
              )
            : section,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
