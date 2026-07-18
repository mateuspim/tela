import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/accent_color.dart';

void main() {
  group('AccentColor', () {
    test('round-trips an rgb value through its hex and back', () {
      expect(AccentColor(0x2c63e0).hex, '#2c63e0');
      expect(AccentColor.fromHex('#2c63e0').rgb, 0x2c63e0);
    });

    test('reads a stored value with or without the leading hash', () {
      expect(AccentColor.fromHex('2c63e0'), AccentColor.fromHex('#2C63E0'));
    });

    test('zero-pads so a dark accent keeps all six digits', () {
      // 0x0000ff must not read back as "#ff": a settings row that loses its
      // width is a different colour on the next launch.
      expect(AccentColor(0x0000ff).hex, '#0000ff');
      expect(AccentColor(0x000000).hex, '#000000');
    });

    test('refuses a value that carries alpha, not just rgb', () {
      // 0xFF2C63E0 is a caller that forgot to strip opacity; masking it would
      // paint a colour they did not choose.
      expect(() => AccentColor(0xFF2C63E0), throwsArgumentError);
      expect(() => AccentColor(-1), throwsArgumentError);
    });

    test('names the offending value and the expected shape when it throws', () {
      expect(
        () => AccentColor.fromHex('#06c'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            allOf(contains('#rrggbb'), contains('#06c')),
          ),
        ),
      );
    });

    test('tryFromHex answers null for absent or malformed rows', () {
      // The storage adapter reads with this: a corrupt row costs the accent,
      // not the app, because a null accent already means "follow Material You".
      expect(AccentColor.tryFromHex(null), isNull);
      expect(AccentColor.tryFromHex('not-a-colour'), isNull);
      expect(AccentColor.tryFromHex('#2c63e0'), AccentColor(0x2c63e0));
    });
  });
}
