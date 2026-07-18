import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/features/settings/accent_picker_sheet.dart';

void main() {
  const Color seed = Color(0xFF2C63E0);

  testWidgets('confirming returns the seeded colour untouched', (
    WidgetTester tester,
  ) async {
    final Color? result = await _openAndConfirm(tester, seed);

    // No drag, so the picker hands back exactly what it opened on.
    expect(result, seed);
  });

  testWidgets('dragging the panel changes the colour it returns', (
    WidgetTester tester,
  ) async {
    Color? result;
    await _open(tester, seed, (Color? c) => result = c);

    // A horizontal drag to the left edge drops saturation to zero — a grey, and
    // certainly not the saturated seed. Horizontal on purpose: a vertical drag
    // on a modal sheet is its own drag-to-dismiss, not the panel's.
    await tester.drag(
      find.bySemanticsLabel('Saturation and brightness'),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this color'));
    await tester.pumpAndSettle();

    expect(result, isNot(seed));
  });
}

/// Opens the picker, taps confirm without touching it, and returns the result.
Future<Color?> _openAndConfirm(WidgetTester tester, Color initial) async {
  Color? result;
  await _open(tester, initial, (Color? c) => result = c);
  await tester.tap(find.text('Use this color'));
  await tester.pumpAndSettle();
  return result;
}

/// Pumps a launcher, opens the picker on [initial], and reports its result to
/// [onResult].
Future<void> _open(
  WidgetTester tester,
  Color initial,
  ValueChanged<Color?> onResult,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => onResult(
                await AccentPickerSheet.show(context, initial: initial),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
