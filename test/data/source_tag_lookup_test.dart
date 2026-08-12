import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/konachan/dio_konachan_source.dart';
import 'package:tela/data/wallhaven/dio_wallhaven_source.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper_details.dart';

/// What a tag lookup costs, per source.
///
/// The two sources differ in a way no interface can hide, and the whole design
/// of `tagsFor` follows from it: a booru's listing already carries every post's
/// tags, while Wallhaven's `/search` carries none at all and each one is a
/// `/w/{id}` against a 45/minute ceiling. So what is pinned here is **request
/// count**, not just the answer.
void main() {
  group('Konachan', () {
    late _CountingAdapter adapter;
    late DioKonachanSource source;

    setUp(() {
      adapter = _CountingAdapter();
      final Dio dio = Dio()..httpClientAdapter = adapter;
      source = DioKonachanSource(dio);
    });

    /// The point of the whole Konachan path: the grid the user is selecting
    /// from has already paid for these.
    test('answers a listed selection with no requests at all', () async {
      adapter.body = <Map<String, dynamic>>[
        _post(id: 1, tags: 'landscape mountains'),
        _post(id: 2, tags: 'landscape city'),
      ];
      await source.search(const SearchQuery());
      final int afterListing = adapter.calls;

      final Map<String, List<WallpaperTag>> tags = await source.tagsFor(
        <String>['1', '2'],
        budget: 25,
      );

      expect(adapter.calls, afterListing, reason: 'a request was spent');
      expect(tags['1']!.map((WallpaperTag t) => t.name), <String>[
        'landscape',
        'mountains',
      ]);
      expect(tags['2']!.map((WallpaperTag t) => t.name), <String>[
        'landscape',
        'city',
      ]);
    });

    test('spends requests only on ids it has never listed', () async {
      adapter.body = <Map<String, dynamic>>[_post(id: 1, tags: 'landscape')];
      await source.search(const SearchQuery());
      final int afterListing = adapter.calls;

      await source.tagsFor(<String>['1', '99'], budget: 25);

      expect(adapter.calls, afterListing + 1);
    });

    test('never spends more requests than the budget allows', () async {
      await source.tagsFor(<String>['1', '2', '3', '4'], budget: 2);

      expect(adapter.calls, 2);
    });
  });

  group('Wallhaven', () {
    late _CountingAdapter adapter;
    late DioWallhavenSource source;

    setUp(() {
      adapter = _CountingAdapter();
      // A base URL, because `wallpaperDetails` asks for the relative `/w/{id}`
      // and Dio rejects that outright without one — which would look exactly
      // like a source that answered nothing.
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://wallhaven.cc/api/v1'))
        ..httpClientAdapter = adapter;
      source = DioWallhavenSource(dio);
    });

    /// Every id is a request here, because `/search` carries no tags — which is
    /// the entire reason the caller passes a budget rather than a selection.
    test('stops at the budget and answers what it got', () async {
      // The captured detail payload the mapper tests use, rather than a
      // hand-written one: a fixture that fails to map looks exactly like a
      // source that answered nothing, which is the wrong thing to be pinning.
      adapter.body = jsonDecode(
        File('test/fixtures/wallpaper_detail.json').readAsStringSync(),
      );

      final Map<String, List<WallpaperTag>> tags = await source.tagsFor(
        <String>['a', 'b', 'c', 'd', 'e'],
        budget: 2,
      );

      expect(adapter.calls, 2);
      expect(tags.length, 2);
    });

    /// A suggestion is a convenience. Losing it must never cost the download
    /// the user actually asked for.
    test('an unreachable source answers empty rather than throwing', () async {
      adapter.status = 500;

      final Map<String, List<WallpaperTag>> tags = await source.tagsFor(
        <String>['a'],
        budget: 5,
      );

      expect(tags, isEmpty);
    });
  });
}

Map<String, dynamic> _post({required int id, required String tags}) {
  return <String, dynamic>{
    'id': id,
    'file_url': 'https://konachan.com/image/$id.jpg',
    'preview_url': 'https://konachan.com/preview/$id.jpg',
    'sample_url': 'https://konachan.com/sample/$id.jpg',
    'jpeg_url': 'https://konachan.com/jpeg/$id.jpg',
    'width': 1920,
    'height': 1080,
    'file_size': 1024,
    'rating': 's',
    'tags': tags,
    'score': 1,
    'author': 'someone',
    'source': '',
  };
}

/// Counts how many requests actually crossed the wire, which is the thing
/// under test — a fake that only shaped answers could not tell a free lookup
/// from an expensive one.
class _CountingAdapter implements HttpClientAdapter {
  int calls = 0;
  int status = 200;
  Object? body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(
      jsonEncode(body ?? <Map<String, dynamic>>[]),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
