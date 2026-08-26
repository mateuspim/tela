import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/localsend/localsend_beam.dart';
import 'package:tela/data/localsend/localsend_wire.dart';
import 'package:tela/domain/models/beam_failure.dart';
import 'package:tela/domain/models/beam_file.dart';
import 'package:tela/domain/models/beam_target.dart';
import 'package:tela/domain/models/purity.dart';

/// A real HTTP server standing in for a LocalSend receiver.
///
/// A real socket rather than a faked transport, deliberately: the thing under
/// test is a wire protocol, and the bugs it can have — a list where v2 wants a
/// map, a missing content-length on a streamed body — live below Dio's API and
/// would be invisible to a recorded `RequestOptions`.
class _FakeReceiver {
  _FakeReceiver({this.acceptedFileIds, this.prepareStatus = 200});

  /// Which file ids get a token. Null means "all of them".
  final Set<String>? acceptedFileIds;

  /// What `/prepare-upload` answers with.
  final int prepareStatus;

  late final HttpServer _server;

  /// Every prepare-upload body received, decoded.
  final List<Map<String, Object?>> prepares = <Map<String, Object?>>[];

  /// Every upload, as (query parameters, bytes received).
  final List<({Map<String, String> query, List<int> bytes})> uploads =
      <({Map<String, String> query, List<int> bytes})>[];

  int get port => _server.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_serve());
  }

  Future<void> _serve() async {
    await for (final HttpRequest request in _server) {
      if (request.uri.path.endsWith('/prepare-upload')) {
        await _handlePrepare(request);
        continue;
      }
      if (request.uri.path.endsWith('/upload')) {
        await _handleUpload(request);
        continue;
      }
      if (request.uri.path.endsWith('/register')) {
        await _handleRegister(request);
        continue;
      }
      request.response.statusCode = 404;
      await request.response.close();
    }
  }

  Future<void> _handlePrepare(HttpRequest request) async {
    final Map<String, Object?> body =
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, Object?>;
    prepares.add(body);
    if (prepareStatus != 200) {
      request.response.statusCode = prepareStatus;
      await request.response.close();
      return;
    }
    final Map<String, Object?> files = body['files']! as Map<String, Object?>;
    final Map<String, String> tokens = <String, String>{
      for (final String id in files.keys)
        if (acceptedFileIds == null || acceptedFileIds!.contains(id))
          id: 'token-$id',
    };
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(<String, Object?>{'sessionId': 'session-1', 'files': tokens}),
    );
    await request.response.close();
  }

  Future<void> _handleUpload(HttpRequest request) async {
    final List<int> bytes = <int>[];
    await request.forEach(bytes.addAll);
    uploads.add((query: request.uri.queryParameters, bytes: bytes));
    await request.response.close();
  }

  Future<void> _handleRegister(HttpRequest request) async {
    await utf8.decoder.bind(request).join();
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(<String, Object?>{
        'alias': 'workstation',
        'version': '2.0',
        'deviceModel': 'Arch',
        'deviceType': 'desktop',
        'fingerprint': 'receiver-fp',
        'download': false,
      }),
    );
    await request.response.close();
  }

  Future<void> stop() => _server.close(force: true);
}

const LocalSendIdentity _identity = LocalSendIdentity(
  alias: 'tela',
  fingerprint: 'tela-fp',
);

LocalSendBeam _beam() => LocalSendBeam(
  dio: Dio(
    BaseOptions(
      validateStatus: (int? status) => status != null && status < 500,
    ),
  ),
  identity: () async => _identity,
);

BeamTarget _targetOn(int port) => BeamTarget(
  alias: 'workstation',
  host: '127.0.0.1',
  port: port,
  fingerprint: 'receiver-fp',
  usesHttps: false,
);

late Directory _tmp;

BeamFile _fileOf(String id, String contents, {Purity purity = Purity.sfw}) {
  final File file = File('${_tmp.path}/$id.jpg')..writeAsStringSync(contents);
  return BeamFile(
    id: id,
    fileName: '$id.jpg',
    path: file.path,
    sizeBytes: file.lengthSync(),
    mimeType: 'image/jpeg',
    purity: purity,
  );
}

void main() {
  setUp(() => _tmp = Directory.systemTemp.createTempSync('beam'));
  tearDown(() => _tmp.deleteSync(recursive: true));

  group('a beam reaches a receiver', () {
    test('sends every accepted file, bytes intact', () async {
      final _FakeReceiver receiver = _FakeReceiver();
      await receiver.start();
      addTearDown(receiver.stop);

      await _beam().send(
        target: _targetOn(receiver.port),
        files: <BeamFile>[
          _fileOf('one', 'first wallpaper'),
          _fileOf('two', 'second wallpaper'),
        ],
      );

      expect(receiver.uploads, hasLength(2));
      expect(
        utf8.decode(receiver.uploads.first.bytes),
        'first wallpaper',
      );
      expect(
        utf8.decode(receiver.uploads.last.bytes),
        'second wallpaper',
      );
    });

    test('carries the session and per-file token on every upload', () async {
      final _FakeReceiver receiver = _FakeReceiver();
      await receiver.start();
      addTearDown(receiver.stop);

      await _beam().send(
        target: _targetOn(receiver.port),
        files: <BeamFile>[_fileOf('one', 'x')],
      );

      expect(receiver.uploads.single.query, <String, String>{
        'sessionId': 'session-1',
        'fileId': 'one',
        'token': 'token-one',
      });
    });

    test('describes files as a map keyed by id, not a list', () async {
      // v2 changed this from v1's list, and a v2 receiver silently rejects a
      // list. Nothing above the wire could catch it.
      final _FakeReceiver receiver = _FakeReceiver();
      await receiver.start();
      addTearDown(receiver.stop);

      await _beam().send(
        target: _targetOn(receiver.port),
        files: <BeamFile>[_fileOf('one', 'hello')],
      );

      final Map<String, Object?> files =
          receiver.prepares.single['files']! as Map<String, Object?>;
      final Map<String, Object?> entry = files['one']! as Map<String, Object?>;
      expect(entry['fileName'], 'one.jpg');
      expect(entry['size'], 5);
      expect(entry['fileType'], 'image/jpeg');
    });

    test('announces itself as a sender that runs no server', () async {
      // `download: false` is not decoration: it tells the receiver not to try
      // reaching back to a server tela does not run.
      final _FakeReceiver receiver = _FakeReceiver();
      await receiver.start();
      addTearDown(receiver.stop);

      await _beam().send(
        target: _targetOn(receiver.port),
        files: <BeamFile>[_fileOf('one', 'x')],
      );

      final Map<String, Object?> info =
          receiver.prepares.single['info']! as Map<String, Object?>;
      expect(info['fingerprint'], 'tela-fp');
      expect(info['version'], '2.0');
      expect(info['download'], isFalse);
    });

    test('reports progress as a running total across the batch', () async {
      final _FakeReceiver receiver = _FakeReceiver();
      await receiver.start();
      addTearDown(receiver.stop);
      final List<int> seen = <int>[];

      await _beam().send(
        target: _targetOn(receiver.port),
        files: <BeamFile>[
          _fileOf('one', '12345'),
          _fileOf('two', '1234567890'),
        ],
        onProgress: seen.add,
      );

      expect(seen, <int>[5, 15]);
    });
  });

  group('a receiver that accepts only part of a batch', () {
    test('sends what was accepted and skips the rest', () async {
      // A user can untick files on their own side. Skipping the untokened ones
      // is the correct reading, not a failure of the whole batch.
      final _FakeReceiver receiver = _FakeReceiver(
        acceptedFileIds: <String>{'one'},
      );
      await receiver.start();
      addTearDown(receiver.stop);

      await _beam().send(
        target: _targetOn(receiver.port),
        files: <BeamFile>[_fileOf('one', 'a'), _fileOf('two', 'b')],
      );

      expect(receiver.uploads, hasLength(1));
      expect(receiver.uploads.single.query['fileId'], 'one');
    });
  });

  group('failures the user can act on', () {
    test('a decline is its own failure, not an error', () async {
      final _FakeReceiver receiver = _FakeReceiver(prepareStatus: 403);
      await receiver.start();
      addTearDown(receiver.stop);

      await expectLater(
        _beam().send(
          target: _targetOn(receiver.port),
          files: <BeamFile>[_fileOf('one', 'x')],
        ),
        throwsA(isA<BeamDeclinedFailure>()),
      );
    });

    test('a busy receiver says so', () async {
      final _FakeReceiver receiver = _FakeReceiver(prepareStatus: 409);
      await receiver.start();
      addTearDown(receiver.stop);

      await expectLater(
        _beam().send(
          target: _targetOn(receiver.port),
          files: <BeamFile>[_fileOf('one', 'x')],
        ),
        throwsA(isA<BeamBusyFailure>()),
      );
    });

    test('a PIN request is distinguishable from a decline', () async {
      final _FakeReceiver receiver = _FakeReceiver(prepareStatus: 401);
      await receiver.start();
      addTearDown(receiver.stop);

      await expectLater(
        _beam().send(
          target: _targetOn(receiver.port),
          files: <BeamFile>[_fileOf('one', 'x')],
        ),
        throwsA(isA<BeamPinRequiredFailure>()),
      );
    });

    test('nothing listening is unreachable, not unexpected', () async {
      await expectLater(
        _beam().send(
          // Port 1 on loopback: reserved, and nothing binds it.
          target: _targetOn(1),
          files: <BeamFile>[_fileOf('one', 'x')],
        ),
        throwsA(isA<BeamUnreachableFailure>()),
      );
    });

    test('an empty batch is a no-op, not a request', () async {
      final _FakeReceiver receiver = _FakeReceiver();
      await receiver.start();
      addTearDown(receiver.stop);

      await _beam().send(
        target: _targetOn(receiver.port),
        files: <BeamFile>[],
      );

      expect(receiver.prepares, isEmpty);
    });
  });

  group('a hand-typed address', () {
    test("answers the receiver's own alias, not the address typed", () async {
      final _FakeReceiver receiver = _FakeReceiver();
      await receiver.start();
      addTearDown(receiver.stop);

      final BeamTarget target = await _beam().sendTo(
        host: '127.0.0.1',
        port: receiver.port,
      );

      expect(target.alias, 'workstation');
      expect(target.fingerprint, 'receiver-fp');
      expect(target.kind, BeamDeviceKind.desktop);
      // What actually answered, not what the payload said it preferred.
      expect(target.usesHttps, isFalse);
    });

    test('refuses an address with nothing on it', () async {
      await expectLater(
        _beam().sendTo(host: '127.0.0.1', port: 1),
        throwsA(isA<BeamUnreachableFailure>()),
      );
    });
  });
}
