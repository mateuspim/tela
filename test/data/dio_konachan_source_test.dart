import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/konachan/dio_konachan_source.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_capabilities.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';

import '../fakes/recording_dio_transport.dart';

/// The adapter under test, wired to a transport that records the URI Dio built.
///
/// No base URL on the Dio: Konachan's host is chosen per request, so the
/// absolute URL the adapter composes is the whole thing under test.
({DioKonachanSource api, RecordingDioTransport transport}) _wired({
  String fixture = 'konachan_post_list.json',
}) {
  final RecordingDioTransport transport = RecordingDioTransport(
    body: File('test/fixtures/$fixture').readAsStringSync(),
  );
  final Dio dio = Dio()..httpClientAdapter = transport;
  return (api: DioKonachanSource(dio), transport: transport);
}

/// The URI [query] actually leaves the device as.
Future<Uri> _sentUriFor(SearchQuery query) async {
  final ({DioKonachanSource api, RecordingDioTransport transport}) wired =
      _wired();
  await wired.api.search(query);
  return wired.transport.lastUri;
}

const PurityFilter _all = PurityFilter(<Purity>{
  Purity.sfw,
  Purity.sketchy,
  Purity.nsfw,
});

void main() {
  group('DioKonachanSource.search — host follows purity', () {
    test('an sfw-only browse reads konachan.net/post.json', () async {
      final Uri uri = await _sentUriFor(
        const SearchQuery(ratios: <RatioChoice>[]),
      );

      expect(uri.host, 'konachan.net');
      expect(uri.path, '/post.json');
    });

    test('a browse that includes nsfw reads konachan.com', () async {
      final Uri uri = await _sentUriFor(
        const SearchQuery(purity: _all, ratios: <RatioChoice>[]),
      );

      expect(uri.host, 'konachan.com');
    });
  });

  group('DioKonachanSource.search — the query reaches the wire intact', () {
    test('sends the tags string as one param Konachan can parse', () async {
      // FakeWallpaperSource records a SearchQuery and konachan_query_test
      // asserts on the map, so neither sees the wire. Konachan silently returns
      // wrong results for a malformed tags value rather than erroring, so a
      // mis-serialised param must be caught here, on the URI itself. The
      // browse-default ratio (9:16) rides along, proving it too survives.
      final Uri uri = await _sentUriFor(const SearchQuery(purity: _all));

      expect(uri.queryParameters['tags'], 'ratio:9:16');
      expect(uri.queryParameters['limit'], isNotNull);
    });

    test('never carries an api key — Konachan needs none', () async {
      final Uri uri = await _sentUriFor(
        const SearchQuery(ratios: <RatioChoice>[]),
      );

      expect(uri.query.toLowerCase(), isNot(contains('key')));
      expect(uri.query.toLowerCase(), isNot(contains('apikey')));
    });

    test('maps the answered array through to a domain page', () async {
      final ({DioKonachanSource api, RecordingDioTransport transport}) wired =
          _wired();

      final WallpaperPage page = await wired.api.search(const SearchQuery());

      expect(page.wallpapers, hasLength(2));
    });
  });

  group('DioKonachanSource.wallpaperDetails', () {
    test('looks the id up on .com as a one-result search', () async {
      // Always the unrestricted host: .net returns [] for a q/e post, which
      // would surface as a mystery empty detail screen (PLAN §18.4).
      final ({DioKonachanSource api, RecordingDioTransport transport}) wired =
          _wired(fixture: 'konachan_single_post.json');

      final WallpaperDetails details = await wired.api.wallpaperDetails(
        '406484',
      );

      final Uri uri = wired.transport.lastUri;
      expect(uri.host, 'konachan.com');
      expect(uri.path, '/post.json');
      expect(uri.queryParameters['tags'], 'id:406484');
      expect(details.favorites, 42);
    });
  });

  group('DioKonachanSource.capabilities — booru-shaped', () {
    late SourceCapabilities capabilities;

    setUp(() {
      capabilities = _wired().api.capabilities;
    });

    test('offers no categories, colours or toplist range', () {
      expect(capabilities.supports(SourceFilter.categories), isFalse);
      expect(capabilities.supports(SourceFilter.colors), isFalse);
      expect(capabilities.supports(SourceFilter.topRange), isFalse);
    });

    test('serves every purity without credentials', () {
      expect(capabilities.purities, <Purity>{
        Purity.sfw,
        Purity.sketchy,
        Purity.nsfw,
      });
      expect(capabilities.credentials, SourceCredentials.none);
      expect(capabilities.needsKeyFor(_all), isFalse);
    });

    test('does not offer random — it takes no seed and repeats images', () {
      expect(capabilities.sortsBy(Sorting.random), isFalse);
      expect(capabilities.sortsBy(Sorting.dateAdded), isTrue);
    });

    test('has no account defaults to sync', () {
      expect(capabilities.syncsAccountDefaults, isFalse);
      expect(_wired().api.accountSettings, throwsUnsupportedError);
    });
  });
}
