import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/resolution.dart';

void main() {
  group('RatioChoice', () {
    test('encodes both dialects Wallhaven takes', () {
      expect(const ExactRatio(16, 9).toApiValue(), '16x9');
      expect(ShapeRatio.portrait.toApiValue(), 'portrait');
      expect(ShapeRatio.landscape.toApiValue(), 'landscape');
    });

    test('unions the list, because `ratios` is a union in the API', () {
      expect(
        RatioChoice.encode(<RatioChoice>[
          const ExactRatio(9, 16),
          const ExactRatio(16, 9),
        ]),
        '9x16,16x9',
      );
    });

    test('encodes "any shape" as no param at all, not an empty one', () {
      // `ratios=` is not how you ask Wallhaven for every shape — you omit it.
      expect(RatioChoice.encode(const <RatioChoice>[]), isNull);
    });

    test('round-trips every shape it offers', () {
      for (final RatioChoice choice in offerableRatios(_phone)) {
        expect(RatioChoice.tryParse(choice.toApiValue()), choice);
      }
    });

    test('reads nothing back out of a value that names nothing', () {
      // Load-bearing: Wallhaven *silently ignores* a ratio it cannot read and
      // answers with an unfiltered grid, so a corrupt literal passed straight
      // through would render as a filter that quietly does nothing.
      expect(RatioChoice.tryParse('bogus'), isNull);
      expect(RatioChoice.tryParse('16x'), isNull);
      expect(RatioChoice.tryParse('16x9x4'), isNull);
      expect(RatioChoice.tryParse('0x9'), isNull);
      expect(RatioChoice.tryParse('-16x9'), isNull);
      expect(RatioChoice.tryParse(''), isNull);
    });

    test('one corrupt ratio costs that ratio, not the list', () {
      expect(RatioChoice.readAll('9x16,bogus,portrait'), <RatioChoice>[
        const ExactRatio(9, 16),
        ShapeRatio.portrait,
      ]);
    });

    test('an empty encoded list is "any shape", not a missing one', () {
      expect(RatioChoice.readAll(''), isEmpty);
    });
  });

  group('ExactRatio.ofScreen', () {
    test('reduces a screen to its ratio', () {
      // A modern phone. 1080x2400 reduces to 9x20 — a shape that appears in no
      // wallpaper site's dropdown, and which Wallhaven honours anyway (verified
      // against the real server, 2026-07-14: `ratios=9x20` returns 24
      // wallpapers, every one of them at ratio 0.45).
      expect(ExactRatio.ofScreen(_phone), const ExactRatio(9, 20));
      expect(
        ExactRatio.ofScreen(const Resolution(1920, 1080)),
        const ExactRatio(16, 9),
      );
    });

    test('takes the standard spelling of its own shape when there is one', () {
      // The tablet the device passes run on. It reduces to 8x5, which Wallhaven
      // honours exactly as it honours 16x10 — so this is not about the server
      // rejecting anything. It is that offerableRatios would otherwise offer
      // *both*: two chips, one filter, and selecting one leaves the other
      // looking unselected.
      expect(
        ExactRatio.ofScreen(const Resolution(2560, 1600)),
        const ExactRatio(16, 10),
      );
      expect(
        const ExactRatio(8, 5).isSameShapeAs(const ExactRatio(16, 10)),
        isTrue,
      );
      expect(const ExactRatio(8, 5), isNot(const ExactRatio(16, 10)));
    });

    test('knows which way up it is', () {
      expect(const ExactRatio(9, 20).isPortrait, isTrue);
      expect(const ExactRatio(16, 9).isPortrait, isFalse);
      expect(const ExactRatio(1, 1).isPortrait, isFalse);
    });
  });

  group('offerableRatios', () {
    test('leads with the device the user is actually holding', () {
      expect(offerableRatios(_phone).first, const ExactRatio(9, 20));
    });

    test('does not offer the device twice when it is a standard shape', () {
      // A tablet at 2560x1600 reduces to 16x10, which is already in the list.
      final List<RatioChoice> offered = offerableRatios(
        const Resolution(2560, 1600),
      );
      expect(
        offered.where((RatioChoice r) => r == const ExactRatio(16, 10)).length,
        1,
      );
      expect(offered.first, const ExactRatio(16, 10));
    });

    test('offers both keywords as well as exact shapes', () {
      final List<RatioChoice> offered = offerableRatios(_phone);
      expect(offered, containsAll(ShapeRatio.values));
      expect(offered, contains(const ExactRatio(16, 9)));
    });

    test('offers nothing Wallhaven cannot honour', () {
      // Every offered value must survive a round trip, or the chip would send a
      // literal the server ignores — the same rule as `offerablePurities`.
      for (final RatioChoice choice in offerableRatios(_phone)) {
        expect(RatioChoice.tryParse(choice.toApiValue()), isNotNull);
      }
    });
  });
}

/// A modern phone, whose reduced ratio is in no standard dropdown.
const Resolution _phone = Resolution(1080, 2400);
