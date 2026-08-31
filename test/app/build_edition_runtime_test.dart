import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/build_edition.dart';

void main() {
  test('compiled edition matches the release command', () {
    const String expected = String.fromEnvironment(
      'EXPECTED_EDITION',
      defaultValue: 'full',
    );
    expect(buildEdition.name, expected);
  });
}
