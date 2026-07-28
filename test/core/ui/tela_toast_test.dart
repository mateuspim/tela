import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/tela_toast.dart';

/// tela's toast: one shape for every message the app reports.
void main() {
  testWidgets('a success and a failure are told apart by more than colour', (
    WidgetTester tester,
  ) async {
    // Colour alone fails anyone who cannot separate the two hues, so each kind
    // carries its own glyph — and the glyph carries a name, because a screen
    // reader gets nothing from either.
    await _pump(tester, 'Wallpaper downloaded.');
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);

    await _pump(tester, 'Could not download.', kind: ToastKind.failure);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
  });

  testWidgets('the icon names its kind for a screen reader', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();

    await _pump(tester, 'Could not download.', kind: ToastKind.failure);

    // The label merges with the message into one node, which is what a
    // screen reader should read out as a unit: "Error, could not download".
    expect(find.bySemanticsLabel(RegExp('Error')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a failure stays up longer than a success', (
    WidgetTester tester,
  ) async {
    // The success usually confirms something the screen already shows; the
    // failure is the only place that news exists.
    await _pump(tester, 'Wallpaper downloaded.');
    final SnackBar success = tester.widget<SnackBar>(find.byType(SnackBar));

    await _pump(tester, 'Could not download.', kind: ToastKind.failure);
    final SnackBar failure = tester.widget<SnackBar>(find.byType(SnackBar));

    expect(failure.duration, greaterThan(success.duration));
  });

  testWidgets('a toast with an action dismisses itself on an ordinary device', (
    WidgetTester tester,
  ) async {
    // The regression, and the one the first fix could not see: Flutter's
    // `persist` defaults to `action != null`, so the toast camped on screen
    // with no accessibility setting involved at all.
    await _pumpPlain(
      tester,
      action: SnackBarAction(label: 'View', onPressed: () {}),
    );
    expect(find.text('Queued 30 wallpapers'), findsOneWidget);

    // Past the success life, plus the exit animation.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('Queued 30 wallpapers'), findsNothing);
  });

  testWidgets('a toast with an action dismisses under accessible navigation', (
    WidgetTester tester,
  ) async {
    await _pumpAccessible(
      tester,
      action: SnackBarAction(label: 'View', onPressed: () {}),
    );
    expect(find.text('Queued 30 wallpapers'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('Queued 30 wallpapers'), findsNothing);
  });

  testWidgets('an actionless toast dismisses too', (WidgetTester tester) async {
    await _pumpAccessible(tester);
    expect(find.text('Queued 30 wallpapers'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('Queued 30 wallpapers'), findsNothing);
  });

  testWidgets('a second toast replaces the first instead of queueing', (
    WidgetTester tester,
  ) async {
    // Batch actions and the quick sheet fire several in a row. Material queues
    // them by default, which leaves the user watching a backlog of stale
    // messages drain — the last of which is the only true one.
    await tester.pumpWidget(_host());
    final ScaffoldMessengerState messenger = tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger));

    showTelaToast(messenger, 'first');
    await tester.pump();
    showTelaToast(messenger, 'second');
    await tester.pumpAndSettle();

    expect(find.text('second'), findsOneWidget);
    expect(find.text('first'), findsNothing);
  });

  testWidgets(
    'it is capped in width on a tablet and unconstrained on a phone',
    (WidgetTester tester) async {
      // A full-width toast across a 1204dip tablet is a stripe, not a message
      // about the thing you just did. A fixed width on a phone would overflow,
      // so there it falls back to the default insets.
      tester.view.physicalSize = const Size(2560, 1600);
      tester.view.devicePixelRatio = 2.125;
      addTearDown(tester.view.reset);
      await _pump(tester, 'Wallpaper downloaded.');
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).width, isNotNull);

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      await _pump(tester, 'Wallpaper downloaded.');
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).width, isNull);
    },
  );
}

/// A device with accessible navigation on, which is where the *first* attempt
/// at the toast regression thought the bug lived.
///
/// It did not: `SnackBar.persist` defaults to `action != null` and never
/// consults this setting, so the queued-download toast — the first one in the
/// app to carry an action — sat there on any device until something else
/// replaced it (owner, 2026-07-27, still reproducing 2026-07-28). Kept because
/// the setting changes how `ScaffoldMessenger` dismisses (instantly, no exit
/// animation) and that path is worth holding onto.
Widget _accessibleHost() {
  return MediaQuery(
    data: const MediaQueryData(accessibleNavigation: true),
    child: _host(),
  );
}

Future<void> _pump(
  WidgetTester tester,
  String message, {
  ToastKind kind = ToastKind.success,
}) async {
  await tester.pumpWidget(_host());
  final ScaffoldMessengerState messenger = tester.state<ScaffoldMessengerState>(
    find.byType(ScaffoldMessenger),
  );
  showTelaToast(messenger, message, kind: kind);
  await tester.pumpAndSettle();
}

Future<void> _pumpAccessible(WidgetTester tester, {SnackBarAction? action}) {
  return _showIn(tester, _accessibleHost(), action: action);
}

/// No accessibility setting at all — the SM-X730 as the owner holds it.
Future<void> _pumpPlain(WidgetTester tester, {SnackBarAction? action}) {
  return _showIn(tester, _host(), action: action);
}

Future<void> _showIn(
  WidgetTester tester,
  Widget host, {
  SnackBarAction? action,
}) async {
  await tester.pumpWidget(host);
  final ScaffoldMessengerState messenger = tester.state<ScaffoldMessengerState>(
    find.byType(ScaffoldMessenger),
  );
  showTelaToast(messenger, 'Queued 30 wallpapers', action: action);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Widget _host() {
  return const MaterialApp(
    localizationsDelegates: <LocalizationsDelegate<Object>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox.shrink()),
  );
}
