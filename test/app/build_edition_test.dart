import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/build_edition.dart';

void main() {
  test('release edition names parse to distinct capability sets', () {
    expect(BuildEdition.parse('play').allowsExplicitContent, isFalse);
    expect(BuildEdition.parse('play').includesKonachan, isFalse);
    expect(BuildEdition.parse('wallhaven').allowsWallhavenCredentials, isTrue);
    expect(BuildEdition.parse('wallhaven').includesKonachan, isFalse);
    expect(BuildEdition.parse('safe').includesKonachan, isTrue);
    expect(BuildEdition.parse('safe').allowsUnrestrictedKonachan, isFalse);
    expect(BuildEdition.parse('full').allowsUnrestrictedKonachan, isTrue);
  });

  test('unknown release edition fails closed', () {
    expect(() => BuildEdition.parse('nightly'), throwsA(isA<ArgumentError>()));
  });
}
