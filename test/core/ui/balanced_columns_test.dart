import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/balanced_columns.dart';

/// A child of a known height, so a test can assert where the flow put it.
Widget _block(String label, double height) {
  return SizedBox(key: Key(label), height: height);
}

Offset _offsetOf(WidgetTester tester, String label) {
  return tester.getTopLeft(find.byKey(Key(label)));
}

Future<void> _pump(
  WidgetTester tester, {
  required int columnCount,
  required List<Widget> children,
  double width = 600,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: BalancedColumns(
            columnCount: columnCount,
            spacing: 10,
            children: children,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('drops each child into the shortest column so far', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      columnCount: 2,
      children: <Widget>[_block('tall', 300), _block('short', 50)],
    );

    // Both start at zero, so the tie sends the first child left; the second
    // then sees 300 on the left and 0 on the right.
    expect(_offsetOf(tester, 'tall'), Offset.zero);
    expect(_offsetOf(tester, 'short'), const Offset(305, 0));
  });

  testWidgets('a later child follows the tall column when it is shorter', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      columnCount: 2,
      children: <Widget>[
        _block('a', 100),
        _block('b', 300),
        _block('c', 50),
      ],
    );

    // a=100 left, b=300 right, so c belongs under a — the static split would
    // have alternated it back to the right instead.
    expect(_offsetOf(tester, 'c'), const Offset(0, 110));
  });

  testWidgets('sizes to the tallest column, with no trailing gap', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      columnCount: 2,
      children: <Widget>[_block('a', 100), _block('b', 300)],
    );

    expect(tester.getSize(find.byType(BalancedColumns)).height, 300);
  });

  testWidgets('one column stacks in source order', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      columnCount: 1,
      children: <Widget>[_block('a', 100), _block('b', 40)],
    );

    expect(_offsetOf(tester, 'a'), Offset.zero);
    expect(_offsetOf(tester, 'b'), const Offset(0, 110));
    expect(tester.getSize(find.byType(BalancedColumns)).width, 600);
  });

  testWidgets('splits the width evenly, minus the gap', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      columnCount: 2,
      children: <Widget>[_block('a', 10)],
    );

    expect(tester.getSize(find.byKey(const Key('a'))).width, 295);
  });

  testWidgets('no children means no height', (WidgetTester tester) async {
    await _pump(tester, columnCount: 2, children: const <Widget>[]);

    expect(tester.getSize(find.byType(BalancedColumns)).height, 0);
  });
}
