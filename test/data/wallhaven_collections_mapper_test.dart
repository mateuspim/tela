import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/wallhaven/wallhaven_mapper.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper_collection.dart';
import 'package:tela/domain/models/wallpaper_page.dart';

/// Captured from the live API on 2026-08-26 — `GET /collections/jrmnt` and
/// `GET /collections/jrmnt/1797738`. Real payloads rather than hand-written
/// ones, per CLAUDE.md: a mapper tested against invented JSON only proves it
/// agrees with the test author.
Map<String, dynamic> _fixture(String name) {
  return jsonDecode(File('test/fixtures/$name').readAsStringSync())
      as Map<String, dynamic>;
}

void main() {
  group('WallhavenMapper.toCollections', () {
    test('maps every row of a real collections listing', () {
      final List<WallpaperCollection> collections =
          WallhavenMapper.toCollections(
            _fixture('collections_list.json'),
            owner: 'jrmnt',
          );

      expect(collections, hasLength(3));
      expect(collections.first.label, 'Default');
      expect(collections.first.count, 479);
      expect(collections.first.views, 26938);
      expect(collections.first.isPublic, isTrue);
    });

    test('addresses each collection by the owner passed in', () {
      // The payload carries no username at all — it is only ever in the
      // request URL — so a ref built without it could not open the contents
      // endpoint that follows.
      final List<WallpaperCollection> collections =
          WallhavenMapper.toCollections(
            _fixture('collections_list.json'),
            owner: 'jrmnt',
          );

      expect(
        collections.last.ref,
        const CollectionRef(
          source: SourceId.wallhaven,
          owner: 'jrmnt',
          id: '1797738',
        ),
      );
      expect(collections.last.ref.key, 'wallhaven:jrmnt:1797738');
    });

    test('reads Wallhaven\'s 0/1 "public" int as a bool', () {
      final List<WallpaperCollection> collections =
          WallhavenMapper.toCollections(<String, dynamic>{
            'data': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 1,
                'label': 'Secret',
                'views': 0,
                'public': 0,
                'count': 3,
              },
            ],
          }, owner: 'someone');

      expect(collections.single.isPublic, isFalse);
    });

    test('refuses a payload whose "data" is not a list', () {
      expect(
        () => WallhavenMapper.toCollections(<String, dynamic>{
          'data': <String, dynamic>{'id': 1},
        }, owner: 'jrmnt'),
        throwsA(isA<UnexpectedResponseFailure>()),
      );
    });
  });

  group('a collection page is a /search page', () {
    test('maps through toPage unchanged, counters and all', () {
      // The whole reason there is no second page mapper: the contents endpoint
      // answers the identical envelope (verified live 2026-08-26). If Wallhaven
      // ever diverges the two, this is the test that notices.
      final WallpaperPage page = WallhavenMapper.toPage(
        _fixture('collection_page.json'),
      );

      expect(page.wallpapers, hasLength(24));
      expect(page.currentPage, 1);
      expect(page.lastPage, 2);
      expect(page.hasMore, isTrue);
      expect(page.total, 46);
    });

    test('carries no shuffle seed, because a collection has no ordering', () {
      final WallpaperPage page = WallhavenMapper.toPage(
        _fixture('collection_page.json'),
      );

      expect(page.seed, isNull);
    });
  });
}
