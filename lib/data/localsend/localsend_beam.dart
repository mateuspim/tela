import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:tela/data/localsend/localsend_wire.dart';
import 'package:tela/domain/models/beam_failure.dart';
import 'package:tela/domain/models/beam_file.dart';
import 'package:tela/domain/models/beam_target.dart';
import 'package:tela/domain/ports/wallpaper_beam.dart';

/// LocalSend v2.2, as a [WallpaperBeam], over Dio and a UDP socket.
///
/// **Sender only.** The protocol needs one party to run an HTTP server and
/// that party is the receiver, so tela opens no listening socket: discovery is
/// an announcement plus whatever answers arrive on the same multicast group,
/// and every transfer is an outbound request. Nothing here can be reached by
/// another device.
///
/// Dio and `dart:io` stop at this file: every `DioException`, `SocketException`
/// and bad status becomes a [BeamFailure] (CLAUDE.md, dependency rule).
class LocalSendBeam implements WallpaperBeam {
  /// Creates the adapter. [dio] carries no base URL — every request is
  /// absolute, because the host is per-target.
  LocalSendBeam({
    required Dio dio,
    required Future<LocalSendIdentity> Function() identity,
    Future<RawDatagramSocket> Function()? openSocket,
  }) : _dio = dio,
       _identity = identity,
       _openSocket = openSocket ?? _bindMulticastSocket;

  final Dio _dio;

  /// Resolved per use rather than held: the fingerprint is generated on first
  /// use and persisted, so it is not knowable when this adapter is built.
  final Future<LocalSendIdentity> Function() _identity;

  /// Injected so a test can drive discovery without a real network — the one
  /// piece of this adapter that cannot be exercised over loopback HTTP.
  final Future<RawDatagramSocket> Function() _openSocket;

  static Future<RawDatagramSocket> _bindMulticastSocket() async {
    final RawDatagramSocket socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      LocalSendIdentity.defaultPort,
      // Every LocalSend client on this machine — and tela's own announcement
      // coming back to itself — shares the port, so exclusivity would fail the
      // bind outright on a device that already has LocalSend installed.
      // `reuseAddress` is already Dart's default; `reusePort` is not.
      reusePort: true,
    );
    socket.joinMulticast(
      InternetAddress(LocalSendIdentity.multicastGroup),
    );
    return socket;
  }

  @override
  Stream<BeamTarget> discover() async* {
    final RawDatagramSocket socket;
    try {
      socket = await _openSocket();
    } on SocketException {
      // A network that will not carry multicast is not an error to report: it
      // is the case `sendTo` exists for, and a chooser showing "no devices"
      // beside a "type an address" field says everything a thrown failure
      // would, without an alarm.
      return;
    }
    // Seen fingerprints, so a receiver announcing on its own timer — LocalSend
    // desktop repeats every few seconds — does not fill the list with itself.
    final Set<String> seen = <String>{};
    try {
      final LocalSendIdentity identity = await _identity();
      _announce(socket, identity);
      await for (final RawSocketEvent event in socket) {
        if (event != RawSocketEvent.read) continue;
        final Datagram? datagram = socket.receive();
        if (datagram == null) continue;
        final BeamTarget? target = _readDatagram(datagram, identity);
        if (target == null) continue;
        if (!seen.add(target.fingerprint)) continue;
        yield target;
      }
    } finally {
      socket.close();
    }
  }

  /// Shouts tela's own info at the group, which is what asks receivers to
  /// answer. Failures are swallowed: an interface that refuses the send is the
  /// same silent network as one that carries it nowhere.
  void _announce(RawDatagramSocket socket, LocalSendIdentity identity) {
    try {
      socket.send(
        utf8.encode(jsonEncode(identity.asAnnouncement())),
        InternetAddress(LocalSendIdentity.multicastGroup),
        LocalSendIdentity.defaultPort,
      );
    } on SocketException {
      return;
    }
  }

  /// Reads one datagram, ignoring anything that is not a device we can address.
  ///
  /// Our own announcement comes back to us on the same group — `reusePort`
  /// guarantees it — so the fingerprint check is not just tidiness: without it
  /// tela discovers itself and offers to beam a phone to itself.
  BeamTarget? _readDatagram(Datagram datagram, LocalSendIdentity identity) {
    final Object? decoded = _tryDecode(utf8.decode(datagram.data));
    if (decoded is! Map<String, Object?>) return null;
    // An announcement asking for answers is a peer looking for us; a reply is
    // a peer answering. Both name a reachable device, so both are usable.
    final BeamTarget? target = readTarget(
      decoded,
      host: datagram.address.address,
    );
    if (target == null) return null;
    return target.fingerprint == identity.fingerprint ? null : target;
  }

  static Object? _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      // Another protocol sharing the group. Not ours, not a problem.
      return null;
    }
  }

  @override
  Future<BeamTarget> sendTo({required String host, required int port}) async {
    final LocalSendIdentity identity = await _identity();
    // `/register` rather than `/info`: it is the same question with tela's own
    // info attached, which is what lets the receiver show who is asking.
    for (final bool https in <bool>[false, true]) {
      final String scheme = https ? 'https' : 'http';
      try {
        final Response<Map<String, dynamic>> response = await _dio
            .post<Map<String, dynamic>>(
              '$scheme://$host:$port/api/localsend/v2/register',
              data: identity.asInfo(),
            );
        final BeamTarget? target = readTarget(
          response.data ?? <String, Object?>{},
          host: host,
        );
        if (target != null) {
          // The payload's own `protocol` describes the receiver's preference;
          // what actually answered is what we must keep using.
          return BeamTarget(
            alias: target.alias,
            host: host,
            port: port,
            fingerprint: target.fingerprint,
            usesHttps: https,
            kind: target.kind,
            model: target.model,
          );
        }
      } on DioException {
        // Fall through and try the other scheme. A desktop LocalSend defaults
        // to https with a self-signed certificate, a headless one often to
        // plain http, and a typed address says which it is.
        continue;
      }
    }
    throw BeamUnreachableFailure('nothing answered at $host:$port');
  }

  @override
  Future<void> send({
    required BeamTarget target,
    required List<BeamFile> files,
    void Function(int bytesSent)? onProgress,
    String? pin,
  }) async {
    if (files.isEmpty) return;
    final _BeamSession session = await _prepare(target, files, pin);
    int sent = 0;
    for (final BeamFile file in files) {
      final String? token = session.tokens[file.id];
      // A receiver may accept a subset — the user can untick files on their
      // side. A file with no token was declined individually, and skipping it
      // is the correct reading, not a failure of the whole batch.
      if (token == null) continue;
      await _upload(target, session.id, file, token);
      sent += file.sizeBytes;
      onProgress?.call(sent);
    }
  }

  /// Asks the receiver to accept the batch, answering the session and tokens.
  Future<_BeamSession> _prepare(
    BeamTarget target,
    List<BeamFile> files,
    String? pin,
  ) async {
    try {
      final Response<Map<String, dynamic>> response = await _dio
          .post<Map<String, dynamic>>(
            '${target.baseUrl}/api/localsend/v2/prepare-upload',
            queryParameters: pin == null ? null : <String, String>{'pin': pin},
            data: <String, Object?>{
              'info': (await _identity()).asInfo(),
              'files': prepareUploadFiles(files),
            },
          );
      // Statuses reach here rather than throwing (see the Dio options in
      // `providers.dart`), because on this protocol they *are* answers: 403 is
      // a person tapping decline, 409 is a receiver mid-transfer. Reading them
      // deliberately is the difference between "they said no" and "something
      // broke".
      _throwForStatus(response.statusCode);
      return _readSession(response.data);
    } on DioException catch (error) {
      throw _toFailure(error);
    }
  }

  _BeamSession _readSession(Map<String, dynamic>? body) {
    final Object? sessionId = body?['sessionId'];
    final Object? tokens = body?['files'];
    if (sessionId is! String || tokens is! Map<String, dynamic>) {
      throw const BeamUnexpectedFailure(
        'the receiver accepted without a session id and file tokens',
      );
    }
    return _BeamSession(
      id: sessionId,
      tokens: <String, String>{
        for (final MapEntry<String, dynamic> entry in tokens.entries)
          if (entry.value is String) entry.key: entry.value as String,
      },
    );
  }

  /// Streams one file's bytes to the receiver.
  ///
  /// Streamed rather than read into memory: a 6K wallpaper is tens of
  /// megabytes and a batch of them would be the OOM PLAN §15 already warns
  /// about, on a path that never needs the whole file at once.
  Future<void> _upload(
    BeamTarget target,
    String sessionId,
    BeamFile file,
    String token,
  ) async {
    final File source = File(file.path);
    try {
      final Response<void> response = await _dio.post<void>(
        '${target.baseUrl}/api/localsend/v2/upload',
        queryParameters: <String, String>{
          'sessionId': sessionId,
          'fileId': file.id,
          'token': token,
        },
        data: source.openRead(),
        options: Options(
          headers: <String, Object>{
            Headers.contentLengthHeader: file.sizeBytes,
          },
          contentType: file.mimeType,
        ),
      );
      _throwForStatus(response.statusCode);
    } on DioException catch (error) {
      throw _toFailure(error);
    } on FileSystemException {
      // Deliberately not naming the path: a beamed explicit file's path is
      // exactly what CLAUDE.md's logging rule forbids recording.
      throw const BeamUnexpectedFailure('a queued file could not be read');
    }
  }

  /// Raises the failure a non-2xx answer means on this protocol.
  void _throwForStatus(int? status) {
    if (status != null && status >= 200 && status < 300) return;
    throw _failureForStatus(status);
  }

  /// Translates transport noise into the failures the UI can act on.
  BeamFailure _toFailure(DioException error) =>
      _failureForStatus(error.response?.statusCode);

  BeamFailure _failureForStatus(int? status) {
    return switch (status) {
      403 => const BeamDeclinedFailure(),
      401 => const BeamPinRequiredFailure(),
      409 => const BeamBusyFailure(),
      // 429 is the receiver rejecting too many PIN attempts, which is still
      // "it wants a PIN and has not got the right one".
      429 => const BeamPinRequiredFailure('too many wrong PIN attempts'),
      null => const BeamUnreachableFailure(),
      _ => BeamUnexpectedFailure('the receiver answered with status $status'),
    };
  }
}

/// One accepted batch: the receiver's session and its per-file tokens.
class _BeamSession {
  const _BeamSession({required this.id, required this.tokens});

  final String id;
  final Map<String, String> tokens;
}
