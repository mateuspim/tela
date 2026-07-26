import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/konachan/dio_konachan_source.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_capabilities.dart';
import 'package:tela/domain/models/source_failure.dart';
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

    test('retries one transient transport failure and then succeeds', () async {
      final _TransientTransport transport = _TransientTransport(
        body: File('test/fixtures/konachan_post_list.json').readAsStringSync(),
        failures: 1,
      );
      final Dio dio = Dio()..httpClientAdapter = transport;
      final DioKonachanSource api = DioKonachanSource(
        dio,
        delay: (_) async {},
      );

      final WallpaperPage page = await api.search(const SearchQuery());

      expect(page.wallpapers, hasLength(2));
      expect(transport.attempts, 2);
    });

    test('stops after one retry when the transport stays down', () async {
      final _TransientTransport transport = _TransientTransport(
        body: '[]',
        failures: 2,
      );
      final Dio dio = Dio()..httpClientAdapter = transport;
      final DioKonachanSource api = DioKonachanSource(
        dio,
        delay: (_) async {},
      );

      await expectLater(
        api.search(const SearchQuery()),
        throwsA(isA<NetworkFailure>()),
      );
      expect(transport.attempts, 2);
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

    test('an id no post carries is a not-found failure', () async {
      // Konachan answers a missing id with 200 and an empty array, not a 404.
      final RecordingDioTransport transport = RecordingDioTransport(body: '[]');
      final Dio dio = Dio()..httpClientAdapter = transport;

      expect(
        () => DioKonachanSource(dio).wallpaperDetails('999999999'),
        throwsA(
          isA<NotFoundFailure>().having(
            (NotFoundFailure f) => f.id,
            'id',
            '999999999',
          ),
        ),
      );
    });
  });

  group('DioKonachanSource.wallpaperIdIn', () {
    late DioKonachanSource api;

    setUp(() => api = _wired().api);

    test('recognizes a decimal post number', () {
      expect(api.wallpaperIdIn('406484'), '406484');
      expect(api.wallpaperIdIn('9'), '9');
    });

    test('trims surrounding whitespace from a paste', () {
      expect(api.wallpaperIdIn('  406484  '), '406484');
    });

    test("rejects Wallhaven's alphanumeric shape", () {
      // The asymmetry is deliberate: Konachan can rule out je9ldp, but
      // Wallhaven cannot rule out 406484 — digits are in its alphabet too.
      expect(api.wallpaperIdIn('je9ldp'), isNull);
    });

    test('rejects a leading zero, which is not how Konachan writes an id', () {
      expect(api.wallpaperIdIn('0406484'), isNull);
      expect(api.wallpaperIdIn('0'), isNull);
    });

    test('rejects a number too long to be a post id', () {
      expect(api.wallpaperIdIn('1234567890'), isNull);
    });

    test('rejects a tag that merely contains digits', () {
      expect(api.wallpaperIdIn('touhou_2'), isNull);
      expect(api.wallpaperIdIn(''), isNull);
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

/// Fails the first [failures] adapter reads as receive timeouts, then answers.
final class _TransientTransport implements HttpClientAdapter {
  _TransientTransport({required this.body, required this.failures});

  final String body;
  final int failures;
  int attempts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    attempts += 1;
    if (attempts <= failures) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
