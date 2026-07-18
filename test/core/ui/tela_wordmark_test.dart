import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/tela_wordmark.dart';

void main() {
  testWidgets('sets the app name in the display face', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const TelaWordmark());

    final Text mark = tester.widget<Text>(find.text('tela'));
    expect(mark.style?.fontFamily, 'Bricolage');
    expect(mark.style?.fontWeight, FontWeight.w700);
  });

  testWidgets('honours an explicit colour for a brand moment', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const TelaWordmark(color: Color(0xFF123456)));

    expect(
      tester.widget<Text>(find.text('tela')).style?.color,
      const Color(0xFF123456),
    );
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}
