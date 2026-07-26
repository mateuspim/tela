import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/network/wallhaven_client.dart';
import 'package:tela/data/wallhaven/dio_wallhaven_source.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/resolution_filter.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/search_tag.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/wallpaper_page.dart';

import '../fakes/recording_dio_transport.dart';

/// The adapter under test, wired to a transport that records what Dio built.
///
/// Real `baseUrl`, because the URI is the thing under test and a fake host
/// would not be the URI tela sends.
({DioWallhavenSource api, RecordingDioTransport transport}) _wired({
  String fixture = 'search_page.json',
}) {
  final RecordingDioTransport transport = RecordingDioTransport(
    body: File('test/fixtures/$fixture').readAsStringSync(),
  );
  final Dio dio = Dio(BaseOptions(baseUrl: WallhavenClient.baseUrl))
    ..httpClientAdapter = transport;
  return (api: DioWallhavenSource(dio), transport: transport);
}

/// The URI [query] actually leaves the device as.
Future<Uri> _sentUriFor(SearchQuery query) async {
  final ({DioWallhavenSource api, RecordingDioTransport transport}) wired =
      _wired();
  await wired.api.search(query);
  return wired.transport.lastUri;
}

void main() {
  group('DioWallhavenSource.search sends what the query built', () {
    test('reaches Wallhaven /search on the documented base URL', () async {
      final Uri uri = await _sentUriFor(const SearchQuery());

      expect(uri.origin, 'https://wallhaven.cc');
      expect(uri.path, '/api/v1/search');
    });

    test('sends an exact ratio as the literal Wallhaven parses', () async {
      // The ratios param has only ever met FakeWallpaperSource, which records a
      // SearchQuery and so cannot see the encoding. Wallhaven *silently
      // ignores* a ratios value it cannot read and answers with an unfiltered
      // grid (real server, 2026-07-16: `ratios=bogus` returns the same listing
      // as no filter), so a mis-encoded param here reads on screen as a filter
      // that does nothing at all — the -id: failure again.
      final Uri uri = await _sentUriFor(
        const SearchQuery(ratios: <RatioChoice>[ExactRatio(9, 20)]),
      );

      expect(uri.queryParameters['ratios'], '9x20');
    });

    test('sends a ratio union as one comma-joined param, not two', () async {
      // Wallhaven reads `ratios=16x9,9x16` as a union. A repeated
      // `ratios=16x9&ratios=9x16` is what Dio emits for a List value, and it is
      // not the same request — this pins the String that RatioChoice.encode
      // hands over staying one param.
      final Uri uri = await _sentUriFor(
        const SearchQuery(
          ratios: <RatioChoice>[ExactRatio(16, 9), ShapeRatio.landscape],
        ),
      );

      expect(uri.queryParametersAll['ratios'], <String>['16x9,landscape']);
    });

    test('percent-encodes the union separator to something Wallhaven still '
        'reads as a comma', () async {
      // Dart's Uri.encodeQueryComponent escapes `,` to %2C, so this is what
      // actually goes out. Confirmed harmless against the real server
      // (2026-07-16): `ratios=16x9%2C9x16` and `ratios=16x9,9x16` return the
      // same listing (total 10619, ratios 0.56 and 1.78) — Wallhaven decodes it
      // before parsing. Pinned because the escape is invisible in the decoded
      // queryParameters above, and a server that stopped decoding it would give
      // us an unfiltered grid with no error.
      final Uri uri = await _sentUriFor(
        const SearchQuery(
          ratios: <RatioChoice>[ExactRatio(16, 9), ExactRatio(9, 16)],
        ),
      );

      expect(uri.query, contains('ratios=16x9%2C9x16'));
    });

    test('sends no ratios param at all for "any shape"', () async {
      final Uri uri = await _sentUriFor(
        const SearchQuery(ratios: <RatioChoice>[]),
      );

      // An empty `ratios=` is not how you ask Wallhaven for every shape.
      expect(uri.queryParameters.containsKey('ratios'), isFalse);
      expect(uri.query, isNot(contains('ratios')));
    });

    test('sends a resolved Automatic resolution as atleast', () async {
      // The path every cold launch takes: forScreen folds the real display
      // metrics in, so this param reaches the real server on every launch.
      final Uri uri = await _sentUriFor(
        const SearchQuery().forScreen(const Resolution(1080, 2400)),
      );

      expect(uri.queryParameters['atleast'], '1080x2400');
    });

    test('sends exact sizes as resolutions, never beside atleast', () async {
      // Send both and Wallhaven honours atleast and silently ignores
      // resolutions (real server, 2026-07-16). ResolutionFilter is sealed so
      // the losing combination is unrepresentable; this is that guarantee
      // observed on the wire.
      final Uri uri = await _sentUriFor(
        SearchQuery(
          resolution: ExactResolutions(const <Resolution>[
            Resolution(2560, 1440),
          ]),
        ),
      );

      expect(uri.queryParameters['resolutions'], '2560x1440');
      expect(uri.queryParameters.containsKey('atleast'), isFalse);
    });

    test('sends an unresolved Automatic resolution as no size param', () async {
      final Uri uri = await _sentUriFor(const SearchQuery());

      expect(uri.queryParameters.containsKey('atleast'), isFalse);
      expect(uri.queryParameters.containsKey('resolutions'), isFalse);
    });

    test('sends a quoted tag in q through the escaping intact', () async {
      // The one param carrying spaces, quotes and a leading +, each of which
      // Dio escapes differently. Round-tripping is the claim: whatever the
      // escape looks like, Wallhaven decodes back to the token tela meant.
      final Uri uri = await _sentUriFor(
        const SearchQuery(
          term: 'sunset',
          tags: <SearchTag>[SearchTag('city lights')],
        ),
      );

      expect(uri.queryParameters['q'], 'sunset +"city lights"');
    });

    test('never puts the API key in the URI', () async {
      // CLAUDE.md hard rule, checked at the wire rather than at the
      // interceptor: the key rides X-API-Key, so no param may name it.
      final Uri uri = await _sentUriFor(const SearchQuery());

      expect(uri.queryParameters.containsKey('apikey'), isFalse);
      expect(uri.query.toLowerCase(), isNot(contains('key')));
    });

    test('maps the answered body through to the domain page', () async {
      // Proves the wire assertions above ran through the real adapter path,
      // not a URI built in isolation.
      final ({DioWallhavenSource api, RecordingDioTransport transport}) wired =
          _wired();

      final WallpaperPage page = await wired.api.search(const SearchQuery());

      expect(page.wallpapers, isNotEmpty);
    });
  });

  group('DioWallhavenSource.wallpaperDetails', () {
    test('sends the id in the path with no query string', () async {
      final ({DioWallhavenSource api, RecordingDioTransport transport}) wired =
          _wired(fixture: 'wallpaper_detail.json');

      await wired.api.wallpaperDetails('e7jvjd');

      expect(wired.transport.lastUri.path, '/api/v1/w/e7jvjd');
      expect(wired.transport.lastUri.query, isEmpty);
    });

    test('a 404 is a not-found id, not a malformed response', () async {
      final RecordingDioTransport transport = RecordingDioTransport(
        body: '{"error":"Nothing here"}',
        statusCode: 404,
      );
      final Dio dio = Dio(BaseOptions(baseUrl: WallhavenClient.baseUrl))
        ..httpClientAdapter = transport;

      expect(
        () => DioWallhavenSource(dio).wallpaperDetails('je9ldq'),
        throwsA(
          isA<NotFoundFailure>().having(
            (NotFoundFailure f) => f.id,
            'id',
            'je9ldq',
          ),
        ),
      );
    });

    test('a 404 from /search stays an unexpected response', () async {
      // Only a single-wallpaper lookup can mean "no such id"; a 404 from the
      // listing endpoint is Wallhaven answering strangely.
      final RecordingDioTransport transport = RecordingDioTransport(
        body: '{"error":"Nothing here"}',
        statusCode: 404,
      );
      final Dio dio = Dio(BaseOptions(baseUrl: WallhavenClient.baseUrl))
        ..httpClientAdapter = transport;

      expect(
        () => DioWallhavenSource(dio).search(const SearchQuery()),
        throwsA(isA<UnexpectedResponseFailure>()),
      );
    });
  });

  group('DioWallhavenSource.wallpaperIdIn', () {
    late DioWallhavenSource api;

    setUp(() => api = _wired().api);

    test('recognizes a real six-character id', () {
      expect(api.wallpaperIdIn('je9ldp'), 'je9ldp');
    });

    test('lowercases what a soft keyboard auto-capitalized', () {
      // Verified on the live API 2026-07-26: GET /w/Je9ldp is a 404 and
      // /w/je9ldp is the wallpaper. Normalizing here is what makes the id a
      // phone actually produces resolve at all.
      expect(api.wallpaperIdIn('Je9ldp'), 'je9ldp');
      expect(api.wallpaperIdIn('JE9LDP'), 'je9ldp');
    });

    test('trims surrounding whitespace from a paste', () {
      expect(api.wallpaperIdIn('  je9ldp  '), 'je9ldp');
    });

    test('rejects ordinary search words of the same length', () {
      // The point of the narrow alphabet: a,b,c,f,h,i,s,t,u are not in it, so
      // most six-letter words cannot be mistaken for an id.
      for (final String word in <String>[
        'sunset',
        'nature',
        'forest',
        'castle',
        'purple',
        'katana',
      ]) {
        expect(api.wallpaperIdIn(word), isNull, reason: word);
      }
    });

    test('rejects the wrong length', () {
      expect(api.wallpaperIdIn('je9ld'), isNull);
      expect(api.wallpaperIdIn('je9ldpq'), isNull);
      expect(api.wallpaperIdIn(''), isNull);
    });

    test('rejects punctuation a URL paste would carry', () {
      expect(api.wallpaperIdIn('w/je9ldp'), isNull);
      expect(api.wallpaperIdIn('je-9ldp'), isNull);
    });

    test('accepts an all-digit id — Konachan-shaped is Wallhaven-shaped', () {
      // Not a bug and worth pinning: digits are in Wallhaven's alphabet, so a
      // six-digit Konachan id is a legitimate Wallhaven id shape. Recognition
      // is per-source and only ever *offers*; the API settles it.
      expect(api.wallpaperIdIn('406484'), '406484');
    });
  });
}
