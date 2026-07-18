import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/shelf_header.dart';

void main() {
  testWidgets('sets the label as a tracked, upper-cased plaque', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const ShelfHeader(label: 'Favorites'));

    expect(find.text('FAVORITES'), findsOneWidget);
    expect(find.text('Favorites'), findsNothing);
  });

  testWidgets('states the count in the accent, apart from the label', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const ShelfHeader(label: 'Favorites', count: 24));

    expect(find.text('· 24'), findsOneWidget);
    // The count is the accent moment: it must not read in the label's ink.
    final Color label = tester
        .widget<Text>(find.text('FAVORITES'))
        .style!
        .color!;
    final Color count = tester.widget<Text>(find.text('· 24')).style!.color!;
    expect(count, isNot(label));
    expect(count, _scheme.primary);
  });

  testWidgets('shows no count when none is given', (WidgetTester tester) async {
    await _pump(tester, const ShelfHeader(label: 'Collections'));

    expect(find.text('COLLECTIONS'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
  });
}

final ColorScheme _scheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF2C63E0),
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorScheme: _scheme),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}
