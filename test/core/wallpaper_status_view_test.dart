import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_status_view.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';

/// Boots [child] with the real localizations, which the view reads its wording
/// from.
Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

/// Builds the failure view for [error], the way a grid does.
Widget _failure(Object? error, {VoidCallback? onRetry}) {
  return Builder(
    builder: (BuildContext context) => WallpaperStatusView.failure(
      l10n: AppLocalizations.of(context),
      error: error,
      onRetry: onRetry ?? () {},
    ),
  );
}

void main() {
  group('WallpaperStatusView', () {
    testWidgets('shows its icon and message', (WidgetTester tester) async {
      await _pump(
        tester,
        const WallpaperStatusView(
          icon: Icons.favorite_border,
          message: 'Nothing saved yet.',
        ),
      );

      expect(find.byIcon(Icons.favorite_border), findsOne);
      expect(find.text('Nothing saved yet.'), findsOne);
    });

    testWidgets('offers no button when there is nothing to try', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const WallpaperStatusView(
          icon: Icons.download_outlined,
          message: 'Nothing downloaded yet.',
        ),
      );

      // An empty shelf is a statement, not a prompt: a button here would have
      // nothing to do.
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('runs its action when the button is tapped', (
      WidgetTester tester,
    ) async {
      int taps = 0;

      await _pump(
        tester,
        WallpaperStatusView(
          icon: Icons.lock_outline,
          message: 'The private library is locked.',
          actionLabel: 'Unlock',
          onAction: () => taps++,
        ),
      );
      await tester.tap(find.text('Unlock'));

      expect(taps, 1);
    });
  });

  group('WallpaperStatusView.failure', () {
    testWidgets('says the network is down, and offers a retry', (
      WidgetTester tester,
    ) async {
      int retries = 0;

      await _pump(
        tester,
        _failure(const NetworkFailure(), onRetry: () => retries++),
      );
      await tester.tap(find.text('Retry'));

      expect(
        find.text("Can't reach Wallhaven. Check your connection."),
        findsOne,
      );
      expect(find.byIcon(Icons.cloud_off_outlined), findsOne);
      expect(retries, 1);
    });

    testWidgets('gives each failure its own icon', (WidgetTester tester) async {
      // Offline, rejected, and throttled are three different things to do next,
      // and the pictogram is the fastest way to tell them apart.
      await _pump(tester, _failure(const InvalidApiKeyFailure()));
      expect(find.byIcon(Icons.key_off_outlined), findsOne);
      expect(find.text('That Wallhaven API key was rejected.'), findsOne);

      await _pump(tester, _failure(const RateLimitedFailure()));
      expect(find.byIcon(Icons.hourglass_empty), findsOne);

      await _pump(tester, _failure(const UnexpectedResponseFailure('boom')));
      expect(find.byIcon(Icons.error_outline), findsOne);
    });

    testWidgets('never leaks a raw error to the user', (
      WidgetTester tester,
    ) async {
      // Not a WallhavenFailure at all: a bug, not a diagnosis. The user gets
      // the generic wording rather than a stack trace.
      await _pump(tester, _failure(StateError('paging controller exploded')));

      expect(find.text('Something went wrong loading wallpapers.'), findsOne);
      expect(find.textContaining('exploded'), findsNothing);
    });

    testWidgets('says the developer message is never shown', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _failure(const UnexpectedResponseFailure('missing "thumbs" object')),
      );

      expect(find.textContaining('thumbs'), findsNothing);
    });
  });
}
