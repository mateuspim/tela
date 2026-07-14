import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/wallhaven/wallhaven_mapper.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';

Map<String, dynamic> _fixture(String name) {
  final String raw = File('test/fixtures/$name').readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

void main() {
  group('WallhavenMapper.toPage', () {
    test('maps a captured /search response', () {
      final WallpaperPage page = WallhavenMapper.toPage(
        _fixture('search_page.json'),
      );

      expect(page.wallpapers, hasLength(2));
      expect(page.currentPage, 2);
      expect(page.lastPage, 37);
      expect(page.seed, 'abc123');
      expect(page.hasMore, isTrue);
    });

    test('maps each wallpaper to the domain shape, not the wire shape', () {
      final WallpaperPage page = WallhavenMapper.toPage(
        _fixture('search_page.json'),
      );
      final Wallpaper first = page.wallpapers.first;

      expect(first.id, 'e7jvjd');
      expect(first.fullImageUrl, endsWith('wallhaven-e7jvjd.jpg'));
      expect(first.thumbSmallUrl, contains('/small/'));
      expect(first.thumbLargeUrl, contains('/lg/'));
      // The grid renders this one: `small` and `large` are fixed-crop and would
      // center-punch a landscape into a close-up.
      expect(first.thumbOriginalUrl, contains('/orig/'));
      expect(first.resolution, const Resolution(3840, 2160));
      expect(first.fileSizeBytes, 1048576);
      expect(first.purity, Purity.sfw);
      expect(first.category, Category.general);
      expect(first.colors, <String>['#660000', '#000000', '#424153']);
      expect(first.isNsfw, isFalse);
    });

    test('handles sketchy/anime and an empty colour list', () {
      final WallpaperPage page = WallhavenMapper.toPage(
        _fixture('search_page.json'),
      );
      final Wallpaper second = page.wallpapers[1];

      expect(second.purity, Purity.sketchy);
      expect(second.category, Category.anime);
      expect(second.colors, isEmpty);
      expect(second.resolution.isPortrait, isTrue);
    });

    test('reports hasMore false on the final page', () {
      final WallpaperPage page = WallhavenMapper.toPage(<String, dynamic>{
        'data': <dynamic>[],
        'meta': <String, dynamic>{'current_page': 37, 'last_page': 37},
      });

      expect(page.hasMore, isFalse);
      expect(page.wallpapers, isEmpty);
    });

    test('fails soft on a payload shape Wallhaven never promised to keep', () {
      // The ToS reserves the right to change the API without notice, so a
      // surprise shape must be a typed failure, not a TypeError in the grid.
      expect(
        () => WallhavenMapper.toPage(<String, dynamic>{'data': 'nope'}),
        throwsA(isA<UnexpectedResponseFailure>()),
      );
      expect(
        () => WallhavenMapper.toPage(<String, dynamic>{
          'data': <dynamic>[
            <String, dynamic>{'id': 'x'},
          ],
        }),
        throwsA(isA<UnexpectedResponseFailure>()),
      );
    });
  });
}
