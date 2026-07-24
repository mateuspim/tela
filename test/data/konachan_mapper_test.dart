import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/konachan/konachan_mapper.dart';
import 'package:tela/data/konachan/konachan_query.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';

/// Decodes a captured fixture to the shape Dio would hand the mapper.
Object? _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync());

/// A minimal but complete post, for the paging-boundary tests that need a
/// specific *count* rather than specific fields.
Map<String, dynamic> _post(int id) => <String, dynamic>{
  'id': id,
  'tags': 'landscape',
  'score': 1,
  'file_size': 1000,
  'file_url': 'https://konachan.com/image/$id.jpg',
  'preview_url': 'https://konachan.com/preview/$id.jpg',
  'sample_url': 'https://konachan.com/sample/$id.jpg',
  'rating': 's',
  'width': 1920,
  'height': 1080,
};

void main() {
  group('KonachanMapper.toPage — fields', () {
    late WallpaperPage page;

    setUp(() {
      page = KonachanMapper.toPage(
        _fixture('konachan_post_list.json'),
        currentPage: 1,
      );
    });

    test('reads every post in the array', () {
      expect(page.wallpapers, hasLength(2));
      expect(page.currentPage, 1);
    });

    test('carries the Konachan source and a string id', () {
      final Wallpaper first = page.wallpapers.first;
      expect(first.source, SourceId.konachan);
      expect(first.id, '406484');
      expect(first.ref.key, 'konachan-406484');
    });

    test('maps the image URLs — no cropped thumb, so small == original', () {
      final Wallpaper w = page.wallpapers.first;
      expect(w.fullImageUrl, contains('/image/'));
      expect(w.thumbLargeUrl, contains('/sample/'));
      expect(w.thumbSmallUrl, contains('/preview/'));
      // Konachan has no separate cropped preview: both non-sample thumbs are
      // the one ratio-preserving preview.
      expect(w.thumbOriginalUrl, w.thumbSmallUrl);
    });

    test('reads the true resolution and file size', () {
      final Wallpaper w = page.wallpapers.first;
      expect(w.resolution.width, 3840);
      expect(w.resolution.height, 2160);
      expect(w.fileSizeBytes, 5242880);
    });

    test('has no category or colours — a booru has neither axis', () {
      final Wallpaper w = page.wallpapers.first;
      expect(w.category, isNull);
      expect(w.colors, isEmpty);
    });
  });

  group('KonachanMapper.toPage — rating maps to purity, failing closed', () {
    test('s → sfw, and a safe post links to the .net host', () {
      final Wallpaper safe = KonachanMapper.toPage(
        _fixture('konachan_post_list.json'),
        currentPage: 1,
      ).wallpapers.first;

      expect(safe.purity, Purity.sfw);
      expect(safe.pageUrl.host, 'konachan.net');
      expect(safe.pageUrl.path, '/post/show/406484');
    });

    test('e → nsfw, and an explicit post links to the .com host', () {
      final Wallpaper explicit = KonachanMapper.toPage(
        _fixture('konachan_post_list.json'),
        currentPage: 1,
      ).wallpapers[1];

      expect(explicit.purity, Purity.nsfw);
      expect(explicit.pageUrl.host, 'konachan.com');
    });

    test('an unknown rating fails closed to nsfw', () {
      // PLAN §17.4: a rating vocabulary tela does not know must not leak past
      // the NSFW rules. Anything but s/q becomes nsfw.
      final WallpaperPage page = KonachanMapper.toPage(
        <Map<String, dynamic>>[
          <String, dynamic>{..._post(1), 'rating': 'x'},
          <String, dynamic>{..._post(2)}..remove('rating'),
        ],
        currentPage: 1,
      );

      expect(page.wallpapers[0].purity, Purity.nsfw);
      expect(page.wallpapers[1].purity, Purity.nsfw);
    });
  });

  group('KonachanMapper.toPage — hasMore from page length', () {
    test('a full page assumes another follows', () {
      final WallpaperPage page = KonachanMapper.toPage(
        List<Map<String, dynamic>>.generate(konachanPageSize, _post),
        currentPage: 1,
      );

      expect(page.hasMore, isTrue);
      // Konachan publishes no page count — nothing to report as lastPage.
      expect(page.lastPage, isNull);
    });

    test('a short page is the end', () {
      final WallpaperPage page = KonachanMapper.toPage(
        List<Map<String, dynamic>>.generate(konachanPageSize - 1, _post),
        currentPage: 2,
      );

      expect(page.hasMore, isFalse);
    });

    test('an empty page is the end', () {
      final WallpaperPage page = KonachanMapper.toPage(
        const <dynamic>[],
        currentPage: 99999,
      );

      expect(page.wallpapers, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });

  group('KonachanMapper.toPage — bad payloads', () {
    test('a non-array body is an UnexpectedResponseFailure', () {
      expect(
        () => KonachanMapper.toPage(
          <String, dynamic>{'error': 'nope'},
          currentPage: 1,
        ),
        throwsA(isA<UnexpectedResponseFailure>()),
      );
    });

    test('a post missing its image url is an UnexpectedResponseFailure', () {
      expect(
        () => KonachanMapper.toPage(
          <Map<String, dynamic>>[_post(1)..remove('file_url')],
          currentPage: 1,
        ),
        throwsA(isA<UnexpectedResponseFailure>()),
      );
    });
  });

  group('KonachanMapper.toDetails', () {
    late WallpaperDetails details;

    setUp(() {
      details = KonachanMapper.toDetails(_fixture('konachan_single_post.json'));
    });

    test('score stands in for favorites; there is no view count', () {
      expect(details.favorites, 42);
      expect(details.views, isNull);
    });

    test('computes the ratio string from width and height', () {
      expect(details.ratio, '1.78');
    });

    test('derives the MIME type from the file extension', () {
      expect(details.fileType, 'image/jpeg');
    });

    test('splits the tags string into names carrying no id', () {
      expect(details.tags.map((WallpaperTag t) => t.name), <String>[
        'landscape',
        'mountains',
        'scenery',
        'no_humans',
        'wide_image',
      ]);
      expect(details.tags.every((WallpaperTag t) => t.id == null), isTrue);
    });

    test('maps the uploader and the credited source', () {
      expect(details.uploader.username, 'kanade');
      expect(details.uploader.group, isEmpty);
      expect(details.uploader.avatarUrl, isEmpty);
      expect(details.source, 'https://www.pixiv.net/artworks/98765432');
    });

    test('derives MIME from the URL when file_ext is absent', () {
      final WallpaperDetails png = KonachanMapper.toDetails(
        <Map<String, dynamic>>[
          <String, dynamic>{
            ..._post(9),
            'file_url': 'https://konachan.com/image/9.png',
          }..remove('file_ext'),
        ],
      );

      expect(png.fileType, 'image/png');
    });

    test('an empty array is a failure, not an empty screen', () {
      // The .net-returns-[] trap (PLAN §18.4): the adapter avoids it by asking
      // .com, but if it ever surfaces it must read as an error, not a blank.
      expect(
        () => KonachanMapper.toDetails(const <dynamic>[]),
        throwsA(isA<UnexpectedResponseFailure>()),
      );
    });
  });
}
