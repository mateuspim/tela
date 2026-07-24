import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/konachan/konachan_query.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/resolution_filter.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/search_tag.dart';

/// The `tags` string [query] encodes to.
String _tagsOf(SearchQuery query) => konachanQueryParameters(query)['tags']!;

void main() {
  group('konachanQueryParameters — paging and page size', () {
    test('sends the requested page and the fixed page size', () {
      final Map<String, String> params = konachanQueryParameters(
        const SearchQuery(page: 3),
      );

      expect(params['page'], '3');
      expect(params['limit'], '$konachanPageSize');
    });
  });

  group(
    'konachanQueryParameters — rating is one term, never one per purity',
    () {
      // The trap PLAN §18.3 documents: `rating:s rating:q` does not OR and does
      // not error — the last token silently wins. Every non-empty subset must
      // be a single positive or negative term.
      test('sfw only → rating:s', () {
        expect(
          _tagsOf(const SearchQuery(ratios: <RatioChoice>[])),
          'rating:s',
        );
      });

      test('sketchy only → rating:q', () {
        expect(
          _tagsOf(
            const SearchQuery(
              purity: PurityFilter(<Purity>{Purity.sketchy}),
              ratios: <RatioChoice>[],
            ),
          ),
          'rating:q',
        );
      });

      test('nsfw only → rating:e', () {
        expect(
          _tagsOf(
            const SearchQuery(
              purity: PurityFilter(<Purity>{Purity.nsfw}),
              ratios: <RatioChoice>[],
            ),
          ),
          'rating:e',
        );
      });

      test('sfw + sketchy → -rating:e', () {
        expect(
          _tagsOf(
            const SearchQuery(
              purity: PurityFilter(<Purity>{Purity.sfw, Purity.sketchy}),
              ratios: <RatioChoice>[],
            ),
          ),
          '-rating:e',
        );
      });

      test('sfw + nsfw → -rating:q', () {
        expect(
          _tagsOf(
            const SearchQuery(
              purity: PurityFilter(<Purity>{Purity.sfw, Purity.nsfw}),
              ratios: <RatioChoice>[],
            ),
          ),
          '-rating:q',
        );
      });

      test('sketchy + nsfw → -rating:s', () {
        expect(
          _tagsOf(
            const SearchQuery(
              purity: PurityFilter(<Purity>{Purity.sketchy, Purity.nsfw}),
              ratios: <RatioChoice>[],
            ),
          ),
          '-rating:s',
        );
      });

      test('all three purities → no rating token at all', () {
        expect(
          _tagsOf(
            const SearchQuery(
              purity: PurityFilter(<Purity>{
                Purity.sfw,
                Purity.sketchy,
                Purity.nsfw,
              }),
              ratios: <RatioChoice>[],
            ),
          ),
          isEmpty,
        );
      });

      test('empty purity set throws, never sends an empty rating', () {
        expect(
          () => konachanQueryParameters(
            const SearchQuery(purity: PurityFilter(<Purity>{})),
          ),
          throwsArgumentError,
        );
      });
    },
  );

  group('konachanQueryParameters — tags are underscore-joined, unquoted', () {
    test('encodes a structural uploader with Konachan syntax', () {
      expect(
        _tagsOf(
          const SearchQuery(
            uploader: 'pym',
            purity: PurityFilter(<Purity>{
              Purity.sfw,
              Purity.sketchy,
              Purity.nsfw,
            }),
            ratios: <RatioChoice>[],
          ),
        ),
        'user:pym',
      );
    });

    test(
      'a multi-word required tag becomes one underscore token, no quotes',
      () {
        // The opposite of SearchTag.token, which quotes for Wallhaven. Konachan
        // splits on spaces and does not understand quotes, so `black hair` must
        // reach it as one token `black_hair`.
        expect(
          _tagsOf(
            const SearchQuery(
              tags: <SearchTag>[SearchTag('black hair')],
              purity: PurityFilter(<Purity>{
                Purity.sfw,
                Purity.sketchy,
                Purity.nsfw,
              }),
              ratios: <RatioChoice>[],
            ),
          ),
          'black_hair',
        );
      },
    );

    test('an excluded tag takes a leading minus', () {
      expect(
        _tagsOf(
          const SearchQuery(
            tags: <SearchTag>[SearchTag('monochrome', TagSense.exclude)],
            purity: PurityFilter(<Purity>{
              Purity.sfw,
              Purity.sketchy,
              Purity.nsfw,
            }),
            ratios: <RatioChoice>[],
          ),
        ),
        '-monochrome',
      );
    });

    test('a blocked tag name is excluded as a slug', () {
      expect(
        _tagsOf(
          const SearchQuery(
            blockedTagNames: <String>{'guro'},
            purity: PurityFilter(<Purity>{
              Purity.sfw,
              Purity.sketchy,
              Purity.nsfw,
            }),
            ratios: <RatioChoice>[],
          ),
        ),
        '-guro',
      );
    });
  });

  group('konachanQueryParameters — size and shape', () {
    test('a minimum resolution becomes width:>= and height:>= tokens', () {
      final String tags = _tagsOf(
        const SearchQuery(
          resolution: AtLeastResolution(Resolution(1920, 1080)),
          purity: PurityFilter(<Purity>{
            Purity.sfw,
            Purity.sketchy,
            Purity.nsfw,
          }),
          ratios: <RatioChoice>[],
        ),
      );

      expect(tags, contains('width:>=1920'));
      expect(tags, contains('height:>=1080'));
    });

    test('an exact-size list is dropped — Konachan cannot express it', () {
      // ExactResolutions has no clean Konachan encoding; the design drops it
      // rather than mis-encode it into a query that returns the wrong grid.
      expect(
        _tagsOf(
          SearchQuery(
            resolution: ExactResolutions(const <Resolution>[
              Resolution(2560, 1440),
            ]),
            purity: const PurityFilter(<Purity>{
              Purity.sfw,
              Purity.sketchy,
              Purity.nsfw,
            }),
            ratios: const <RatioChoice>[],
          ),
        ),
        isEmpty,
      );
    });

    test('an exact ratio becomes ratio:W:H', () {
      expect(
        _tagsOf(
          const SearchQuery(
            ratios: <RatioChoice>[ExactRatio(16, 9)],
            purity: PurityFilter(<Purity>{
              Purity.sfw,
              Purity.sketchy,
              Purity.nsfw,
            }),
          ),
        ),
        'ratio:16:9',
      );
    });

    test(
      'the portrait/landscape keywords are dropped — no Konachan equivalent',
      () {
        expect(
          _tagsOf(
            const SearchQuery(
              ratios: <RatioChoice>[ShapeRatio.portrait],
              purity: PurityFilter(<Purity>{
                Purity.sfw,
                Purity.sketchy,
                Purity.nsfw,
              }),
            ),
          ),
          isEmpty,
        );
      },
    );
  });

  group('konachanQueryParameters — order', () {
    test('newest-first sends no order token (it is the default)', () {
      expect(
        _tagsOf(
          const SearchQuery(
            purity: PurityFilter(<Purity>{
              Purity.sfw,
              Purity.sketchy,
              Purity.nsfw,
            }),
            ratios: <RatioChoice>[],
          ),
        ),
        isEmpty,
      );
    });

    test('views and favorites both fold onto order:score', () {
      for (final Sorting sorting in <Sorting>[
        Sorting.views,
        Sorting.favorites,
      ]) {
        expect(
          _tagsOf(
            SearchQuery(
              sorting: sorting,
              purity: const PurityFilter(<Purity>{
                Purity.sfw,
                Purity.sketchy,
                Purity.nsfw,
              }),
              ratios: const <RatioChoice>[],
            ),
          ),
          'order:score',
          reason: '$sorting should map to order:score',
        );
      }
    });

    test('an unsupported sorting throws rather than reaching the wire', () {
      // random/relevance/toplist/hot are declared unsupported in the
      // capabilities and must never be encoded — order:random in particular
      // takes no seed and repeats images across pages (PLAN §18.3).
      for (final Sorting sorting in <Sorting>[
        Sorting.random,
        Sorting.relevance,
        Sorting.toplist,
        Sorting.hot,
      ]) {
        expect(
          () => konachanQueryParameters(SearchQuery(sorting: sorting)),
          throwsArgumentError,
          reason: '$sorting is unsupported',
        );
      }
    });
  });

  group('KonachanHost.forPurity — safe browses go to the safe host', () {
    test('sfw-only reads konachan.net', () {
      expect(KonachanHost.forPurity(PurityFilter.sfwOnly), 'konachan.net');
    });

    test('anything wider than sfw reads konachan.com', () {
      expect(
        KonachanHost.forPurity(
          const PurityFilter(<Purity>{Purity.sfw, Purity.sketchy}),
        ),
        'konachan.com',
      );
      expect(
        KonachanHost.forPurity(const PurityFilter(<Purity>{Purity.nsfw})),
        'konachan.com',
      );
    });
  });
}
