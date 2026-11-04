import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/offload_run.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/features/settings/offload_progress_panel.dart';

void main() {
  const int gib = 1 << 30;

  /// A quarter of 64 GB in ten minutes: 30 minutes left at 27.3 MB/s. The
  /// owner asked for exactly these during a 65 GB move — a progress report,
  /// the speed, and how much is still to go.
  testWidgets('a copy reports its share, time left, data and speed', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const OffloadRun(
        phase: OffloadPhase.copying,
        total: 7298,
        copied: 1234,
        bytes: 64 * gib,
        copiedBytes: 16 * gib,
        elapsed: Duration(minutes: 10),
      ),
    );

    expect(find.text('25% done'), findsOneWidget);
    expect(find.text('About 30 min left'), findsOneWidget);
    expect(find.text('1,234 of 7,298'), findsOneWidget);
    expect(find.text('16.0 GB of 64.0 GB'), findsOneWidget);
    expect(find.text('27.3 MB/s'), findsOneWidget);
    expect(find.text('10 min'), findsOneWidget);
  });

  testWidgets('the first seconds promise no estimate', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const OffloadRun(
        phase: OffloadPhase.copying,
        total: 10,
        copied: 1,
        bytes: 10 * gib,
        copiedBytes: gib,
        elapsed: Duration(seconds: 2),
      ),
    );

    expect(find.text('Working out time left…'), findsOneWidget);
    expect(find.text('Measuring…'), findsOneWidget);
  });

  testWidgets('a stop request is still explained under the report', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const OffloadRun(phase: OffloadPhase.copying, total: 4, stopping: true),
    );

    expect(find.text('Finishing the file in flight…'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, OffloadRun run) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: OffloadProgressPanel(run: run)),
      ),
    ),
  );
}
