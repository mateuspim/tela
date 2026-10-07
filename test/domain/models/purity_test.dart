import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/purity.dart';

void main() {
  group('PurityFilter storage', () {
    test('round-trips through the sfw-sketchy-nsfw mask', () {
      const PurityFilter filter = PurityFilter(<Purity>{
        Purity.sfw,
        Purity.nsfw,
      });

      expect(filter.encodeStored(), '101');
      expect(PurityFilter.tryParseStored('101')?.purities, filter.purities);
    });

    test('answers null for a mask that is not one', () {
      expect(PurityFilter.tryParseStored('000'), isNull);
      expect(PurityFilter.tryParseStored('1x1'), isNull);
      expect(PurityFilter.tryParseStored('11'), isNull);
    });
  });

  group('withoutNsfw', () {
    test('takes explicit out and keeps the rest', () {
      const PurityFilter filter = PurityFilter(<Purity>{
        Purity.sketchy,
        Purity.nsfw,
      });

      expect(filter.withoutNsfw().purities, <Purity>{Purity.sketchy});
    });

    test('falls back to safe when explicit was all there was', () {
      const PurityFilter filter = PurityFilter(<Purity>{Purity.nsfw});

      expect(filter.withoutNsfw().purities, <Purity>{Purity.sfw});
    });
  });
}
