import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/wallhaven/wallhaven_query.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/resolution_filter.dart';
import 'package:tela/domain/models/search_query.dart';

void main() {
  group('ResolutionFilter params', () {
    test('automatic asks for no size at all', () {
      // It cannot: the domain has no idea how big the screen is. `forScreen` is
      // what answers it, at the one place that can.
      final Map<String, String> params = _params(const AutomaticResolution());

      expect(params.containsKey('atleast'), isFalse);
      expect(params.containsKey('resolutions'), isFalse);
    });

    test('at-least sends `atleast`', () {
      expect(
        _params(const AtLeastResolution(Resolution(1080, 2400)))['atleast'],
        '1080x2400',
      );
    });

    test('exactly sends `resolutions`, unioned', () {
      expect(
        _params(
          ExactResolutions(const <Resolution>[
            Resolution(1920, 1080),
            Resolution(2560, 1440),
          ]),
        )['resolutions'],
        '1920x1080,2560x1440',
      );
    });

    test('never sends both `atleast` and `resolutions`', () {
      // The load-bearing one, and the reason the filter is sealed. Wallhaven
      // honours `atleast` and *silently ignores* `resolutions` when both arrive
      // (real server, 2026-07-14), so the combination that loses must not be
      // expressible. Being a sealed type, this is a proof rather than a check.
      for (final ResolutionFilter filter in <ResolutionFilter>[
        const AutomaticResolution(),
        const AtLeastResolution(Resolution(1080, 2400)),
        ExactResolutions(const <Resolution>[Resolution(1920, 1080)]),
      ]) {
        final Map<String, String> params = _params(filter);
        expect(
          params.containsKey('atleast') && params.containsKey('resolutions'),
          isFalse,
        );
      }
    });

    test('refuses an exact filter with no sizes in it', () {
      // `resolutions=` with nothing after it is a malformed request, not a
      // wider listing.
      expect(
        () => ExactResolutions(const <Resolution>[]),
        throwsAssertionError,
      );
    });
  });

  group('ResolutionFilter storage', () {
    test('round-trips each of the three', () {
      for (final ResolutionFilter filter in <ResolutionFilter>[
        const AutomaticResolution(),
        const AtLeastResolution(Resolution(1080, 2400)),
        ExactResolutions(const <Resolution>[
          Resolution(1920, 1080),
          Resolution(2560, 1440),
        ]),
      ]) {
        expect(ResolutionFilter.tryParse(filter.encode()), filter);
      }
    });

    test('stores the wire literals, readable in a sqlite3 shell', () {
      expect(const AutomaticResolution().encode(), 'auto');
      expect(
        const AtLeastResolution(Resolution(1080, 2400)).encode(),
        'atleast:1080x2400',
      );
      expect(
        ExactResolutions(const <Resolution>[Resolution(1920, 1080)]).encode(),
        'exact:1920x1080',
      );
    });

    test('reads nothing back out of a row that names nothing', () {
      expect(ResolutionFilter.tryParse(''), isNull);
      expect(ResolutionFilter.tryParse('nonsense'), isNull);
      expect(ResolutionFilter.tryParse('atleast:'), isNull);
      expect(ResolutionFilter.tryParse('atleast:wide'), isNull);
      expect(ResolutionFilter.tryParse('exact:0x0'), isNull);
      expect(ResolutionFilter.tryParse('sideways:1920x1080'), isNull);
    });

    test('one unreadable size costs the whole exact filter, not just it', () {
      // Deliberately unlike the ratios, which drop a bad entry and keep the
      // rest. An exact list is *exact*: silently dropping one leaves a filter
      // that asks for a different set of wallpapers, not a smaller one.
      expect(ResolutionFilter.tryParse('exact:1920x1080,bogus'), isNull);
    });
  });

  group('SearchQuery.forScreen', () {
    test('answers Automatic with the screen it is running on', () {
      final SearchQuery query = const SearchQuery().forScreen(_phone);

      expect(query.resolution, const AtLeastResolution(_phone));
      expect(wallhavenQueryParameters(query)['atleast'], '1080x2400');
    });

    test('leaves a filter the user chose exactly as it is', () {
      // It resolves the default; it does not overrule a choice. A user who
      // asked for 4K must not have their phone's screen substituted for it.
      const SearchQuery chosen = SearchQuery(
        resolution: AtLeastResolution(Resolution(3840, 2160)),
      );

      expect(chosen.forScreen(_phone), chosen);
      expect(
        wallhavenQueryParameters(chosen.forScreen(_phone))['atleast'],
        '3840x2160',
      );
    });

    test('leaves an exact filter alone too, and sends no atleast with it', () {
      final SearchQuery exact = SearchQuery(
        resolution: ExactResolutions(const <Resolution>[
          Resolution(1920, 1080),
        ]),
      ).forScreen(_phone);

      final Map<String, String> params = wallhavenQueryParameters(exact);
      expect(params['resolutions'], '1920x1080');
      expect(params.containsKey('atleast'), isFalse);
    });
  });

  group('offerableResolutions', () {
    test(
      'leads with the shape of the screen, and offers the screen itself',
      () {
        final List<ResolutionBucket> buckets = offerableResolutions(_phone);

        // A 9x20 phone has no standard ladder, so it gets its own bucket. That
        // "exactly the size I am holding" is offerable at all is the point.
        expect(buckets.first.ratio, const ExactRatio(9, 20));
        expect(buckets.first.sizes, contains(_phone));
      },
    );

    test("puts the screen in its shape's ladder when it has one", () {
      // A 1920x1080 laptop is 16x9, which does have a ladder — and 1920x1080 is
      // already in it, so it must not appear twice.
      final List<ResolutionBucket> buckets = offerableResolutions(
        const Resolution(1920, 1080),
      );

      expect(buckets.first.ratio, const ExactRatio(16, 9));
      expect(
        buckets.first.sizes
            .where((Resolution s) => s == const Resolution(1920, 1080))
            .length,
        1,
      );
    });

    test('offers no size Wallhaven has no wallpapers at', () {
      // `resolutions` is an exact match, so an unpopular size is not a narrower
      // listing — it is an *empty* one. 720x1280 has zero wallpapers on the
      // real server, which is why the portrait ladder starts at 1080p.
      final Iterable<Resolution> every = offerableResolutions(
        _phone,
      ).expand((ResolutionBucket bucket) => bucket.sizes);

      expect(every, isNot(contains(const Resolution(720, 1280))));
      expect(every, isNot(contains(const Resolution(1280, 720))));
    });

    test('every offered size really is the shape it is filed under', () {
      // Within a tolerance, and the tolerance is the point: Wallhaven's `21x9`
      // is a *family*, not an exact ratio. Neither 2560x1080 (64x27) nor
      // 3440x1440 (43x18) reduces to 21x9, and `ratios=21x9` returns both — so
      // the bucket headings are Wallhaven's own labels, and they are the ones
      // that actually find the sizes under them. A size in the wrong bucket,
      // though, would be a chip that filters out the thing it is sitting next
      // to.
      for (final ResolutionBucket bucket in offerableResolutions(_phone)) {
        final double heading = bucket.ratio.width / bucket.ratio.height;
        for (final Resolution size in bucket.sizes) {
          final double actual = size.width / size.height;
          expect(
            (actual - heading).abs() / heading,
            lessThan(0.03),
            reason: '$size does not belong under ${bucket.ratio}',
          );
        }
      }
    });
  });
}

/// A modern phone: 9x20, a shape with no standard resolution ladder.
const Resolution _phone = Resolution(1080, 2400);

/// The size params one filter produces, read off a whole query — the encoder
/// takes a [SearchQuery], since only a query knows which source is asking.
Map<String, String> _params(ResolutionFilter filter) =>
    wallhavenQueryParameters(SearchQuery(resolution: filter));
