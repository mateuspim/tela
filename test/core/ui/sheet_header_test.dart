import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/sheet_header.dart';

void main() {
  group('SheetHeader', () {
    testWidgets('shows its title', (WidgetTester tester) async {
      await _pump(tester, 'Where files are saved');
      expect(find.text('Where files are saved'), findsOneWidget);
    });

    // The whole point of the widget: the title must not carry a ListTile's
    // bodyLarge weight, which made it read as a disabled first option.
    testWidgets('is not a ListTile, and reads as a muted caption', (
      WidgetTester tester,
    ) async {
      await _pump(tester, 'Download to');

      expect(
        find.descendant(
          of: find.byType(SheetHeader),
          matching: find.byType(ListTile),
        ),
        findsNothing,
      );

      final BuildContext context = tester.element(find.byType(SheetHeader));
      final ThemeData theme = Theme.of(context);
      final Text text = tester.widget<Text>(find.text('Download to'));
      expect(text.style?.fontSize, theme.textTheme.titleSmall?.fontSize);
      expect(text.style?.color, theme.colorScheme.onSurfaceVariant);
    });

    testWidgets('lines up on the left even in a centring column', (
      WidgetTester tester,
    ) async {
      // Every chooser sheet is a Column, which centres by default: the caption
      // sat in the middle of the sheet above left-aligned rows.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(children: <Widget>[SheetHeader(title: 'Share')]),
          ),
        ),
      );

      expect(tester.getTopLeft(find.text('Share')).dx, 16);
    });
  });
}

Future<void> _pump(WidgetTester tester, String title) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SheetHeader(title: title)),
    ),
  );
}
