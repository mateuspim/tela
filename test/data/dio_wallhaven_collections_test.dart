import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/network/wallhaven_client.dart';
import 'package:tela/data/wallhaven/dio_wallhaven_source.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper_collection.dart';

import '../fakes/recording_dio_transport.dart';

/// The adapter wired to a transport that records the URI Dio actually built.
///
/// Real `baseUrl`: the URI is the thing under test, and a fake host would not
/// be the URI tela sends. Same seam as `dio_wallhaven_source_test.dart` — it
/// sits *below* query serialization, which is exactly where
/// `FakeWallpaperSource` cannot see.
({DioWallhavenSource api, RecordingDioTransport transport}) _wired(
  String fixture,
) {
  final RecordingDioTransport transport = RecordingDioTransport(
    body: File('test/fixtures/$fixture').readAsStringSync(),
  );
  final Dio dio = Dio(BaseOptions(baseUrl: WallhavenClient.baseUrl))
    ..httpClientAdapter = transport;
  return (api: DioWallhavenSource(dio), transport: transport);
}

const CollectionRef _interiors = CollectionRef(
  source: SourceId.wallhaven,
  owner: 'jrmnt',
  id: '1797738',
);

void main() {
  group('DioWallhavenSource.collectionsOf', () {
    test('asks the documented per-username route', () async {
      final ({DioWallhavenSource api, RecordingDioTransport transport}) wired =
          _wired('collections_list.json');

      await wired.api.collectionsOf('jrmnt');

      expect(wired.transport.lastUri.path, '/api/v1/collections/jrmnt');
    });

    test('sends no query parameters at all', () async {
      // The key rides the X-API-Key header (CLAUDE.md), and this endpoint takes
      // nothing else. An `?apikey=` here would be the exact leak that rule
      // exists to prevent.
      final ({DioWallhavenSource api, RecordingDioTransport transport}) wired =
          _wired('collections_list.json');

      await wired.api.collectionsOf('jrmnt');

      expect(wired.transport.lastUri.queryParameters, isEmpty);
    });
  });

  group('DioWallhavenSource.collectionPage', () {
    test('asks the owner/id contents route', () async {
      final ({DioWallhavenSource api, RecordingDioTransport transport}) wired =
          _wired('collection_page.json');

      await wired.api.collectionPage(
        _interiors,
        page: 2,
        purity: PurityFilter.sfwOnly,
      );

      expect(
        wired.transport.lastUri.path,
        '/api/v1/collections/jrmnt/1797738',
      );
    });

    test('sends purity and page, and nothing else whatsoever', () async {
      // The load-bearing test of this whole feature. Wallhaven accepts
      // `categories`, `atleast`, `ratios`, `sorting` and `order` on this
      // endpoint and *silently ignores* every one of them — measured live
      // 2026-08-26 against collection jrmnt/585550, where each left the total
      // at 447 and the order untouched, and stated in Wallhaven's own API
      // reference ("only the 'purity' filter will be available"). A param that
      // leaks in here would read on screen as a filter that does nothing.
      final ({DioWallhavenSource api, RecordingDioTransport transport}) wired =
          _wired('collection_page.json');

      await wired.api.collectionPage(
        _interiors,
        page: 3,
        purity: const PurityFilter(<Purity>{Purity.sfw, Purity.sketchy}),
      );

      expect(wired.transport.lastUri.queryParameters, <String, String>{
        'purity': '110',
        'page': '3',
      });
    });

    test('encodes purity as the same three bits /search uses', () async {
      final ({DioWallhavenSource api, RecordingDioTransport transport}) wired =
          _wired('collection_page.json');

      await wired.api.collectionPage(
        _interiors,
        page: 1,
        purity: const PurityFilter(<Purity>{Purity.nsfw}),
      );

      expect(wired.transport.lastUri.queryParameters['purity'], '001');
    });
  });

  group('failures keep their meaning', () {
    test('a 404 on a username names that username, not a wallpaper', () async {
      // Wallhaven answers an unknown username, an account with nothing public,
      // and a keyless read with the identical 404 body (measured live). The
      // adapter reports what was asked for rather than inventing a distinction
      // the API does not make.
      final RecordingDioTransport transport = RecordingDioTransport(
        body: '{"error":"Nothing here"}',
        statusCode: 404,
      );
      final Dio dio = Dio(BaseOptions(baseUrl: WallhavenClient.baseUrl))
        ..httpClientAdapter = transport;

      await expectLater(
        DioWallhavenSource(dio).collectionsOf('nobody'),
        throwsA(
          isA<NotFoundFailure>().having(
            (NotFoundFailure f) => f.id,
            'id',
            'nobody',
          ),
        ),
      );
    });

    test('a 404 on contents names the whole collection key', () async {
      final RecordingDioTransport transport = RecordingDioTransport(
        body: '{"error":"Nothing here"}',
        statusCode: 404,
      );
      final Dio dio = Dio(BaseOptions(baseUrl: WallhavenClient.baseUrl))
        ..httpClientAdapter = transport;

      await expectLater(
        DioWallhavenSource(dio).collectionPage(
          _interiors,
          page: 1,
          purity: PurityFilter.sfwOnly,
        ),
        throwsA(
          isA<NotFoundFailure>().having(
            (NotFoundFailure f) => f.id,
            'id',
            'wallhaven:jrmnt:1797738',
          ),
        ),
      );
    });
  });
}
