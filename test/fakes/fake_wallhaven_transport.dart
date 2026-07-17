import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A Dio [HttpClientAdapter] that answers from memory and records the request
/// Dio actually built.
///
/// Sits *below* Dio's query serialization, and that is the whole point.
/// `FakeWallhavenApi` records a `SearchQuery` and `SearchQuery`'s own tests
/// assert on the param **map** — so between them nothing can see what that map
/// is encoded into on the wire. A param Dio dropped, repeated, or escaped into
/// something Wallhaven reads as garbage would pass both. This captures
/// [RequestOptions.uri]: the literal URI the transport would have sent.
///
/// ```dart
/// final FakeWallhavenTransport transport = FakeWallhavenTransport(body: json);
/// dio.httpClientAdapter = transport;
/// await api.search(const SearchQuery());
/// transport.lastUri.queryParameters['ratios']; // '9x16'
/// ```
class FakeWallhavenTransport implements HttpClientAdapter {
  /// Creates a transport answering every request with [body] and [statusCode].
  FakeWallhavenTransport({this.body = '{}', this.statusCode = 200});

  /// The JSON every request is answered with.
  final String body;

  /// The status every request is answered with.
  final int statusCode;

  /// Every request Dio built, oldest first.
  final List<RequestOptions> receivedRequests = <RequestOptions>[];

  /// The URI of the most recent request — what would have left the device.
  Uri get lastUri => receivedRequests.last.uri;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    receivedRequests.add(options);
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
