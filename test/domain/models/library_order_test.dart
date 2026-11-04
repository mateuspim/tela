import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/library_order.dart';

void main() {
  final DateTime monday = DateTime.utc(2026, 11, 2);
  final DateTime tuesday = DateTime.utc(2026, 11, 3);
  final List<(String, DateTime)> saved = <(String, DateTime)>[
    ('b', monday),
    ('c', tuesday),
    ('a', monday),
  ];

  List<String> keys(LibraryOrder order) => order
      .sorted(
        saved,
        savedAt: ((String, DateTime) item) => item.$2,
        tieBreak: ((String, DateTime) item) => item.$1,
      )
      .map(((String, DateTime) item) => item.$1)
      .toList();

  test('newest first puts the latest save first', () {
    expect(keys(LibraryOrder.newestFirst), <String>['c', 'a', 'b']);
  });

  test('oldest first puts the earliest save first', () {
    expect(keys(LibraryOrder.oldestFirst), <String>['a', 'b', 'c']);
  });

  test(
    'ties break the same way in both orders, so a grid never reshuffles',
    () {
      expect(keys(LibraryOrder.newestFirst).sublist(1), <String>['a', 'b']);
      expect(keys(LibraryOrder.oldestFirst).sublist(0, 2), <String>['a', 'b']);
    },
  );

  test('leaves the input list alone', () {
    keys(LibraryOrder.oldestFirst);
    expect(saved.first.$1, 'b');
  });

  test('parses stored names, and answers null for anything else', () {
    expect(LibraryOrder.tryFromName('oldestFirst'), LibraryOrder.oldestFirst);
    expect(LibraryOrder.tryFromName('sideways'), isNull);
    expect(LibraryOrder.tryFromName(null), isNull);
  });
}
