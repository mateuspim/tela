import 'package:tela/domain/models/beam_file.dart';
import 'package:tela/domain/models/beam_target.dart';

/// LocalSend's own identity for this installation of tela.
///
/// The values a receiver shows in its "accept?" prompt, so they have to read
/// as an app rather than a code name. [fingerprint] identifies *this device*
/// to the protocol; under plain `http` the spec asks only for a random string,
/// which is what tela sends — it never runs a server, so there is no
/// certificate to hash and nothing for the value to authenticate.
class LocalSendIdentity {
  /// Creates the identity announced to every receiver.
  const LocalSendIdentity({required this.alias, required this.fingerprint});

  /// The name a receiver displays for this phone.
  final String alias;

  /// A stable random string identifying this install. See the class doc.
  final String fingerprint;

  /// The protocol version tela speaks. Bump only alongside the payloads.
  static const String protocolVersion = '2.0';

  /// LocalSend's registered port, for both the multicast group and HTTP.
  static const int defaultPort = 53317;

  /// The multicast group the spec pins.
  ///
  /// `224.0.0.0/24` specifically, because some Android builds reject joining
  /// any other group — the protocol says so, and this is Android-first.
  static const String multicastGroup = '224.0.0.167';

  /// This device, as the `info` object every payload carries.
  ///
  /// `port` and `protocol` describe a server tela does not run, and `download`
  /// is false for the same reason: they are required fields, and answering
  /// them honestly is what stops a receiver trying to reach back.
  Map<String, Object?> asInfo() => <String, Object?>{
    'alias': alias,
    'version': protocolVersion,
    'deviceModel': 'tela',
    'deviceType': 'mobile',
    'fingerprint': fingerprint,
    'port': defaultPort,
    'protocol': 'http',
    'download': false,
  };

  /// This device, as the UDP announcement that asks receivers to answer.
  Map<String, Object?> asAnnouncement() => <String, Object?>{
    ...asInfo(),
    'announce': true,
  };
}

/// Reads a device's self-description into a [BeamTarget].
///
/// [host] is passed in rather than read from the payload because the payload
/// has none: a datagram's sender address and an HTTP response's peer are the
/// only places the address exists, and both are the caller's to know.
///
/// Answers null for a payload with no fingerprint — the one field target
/// identity depends on — rather than inventing one, which would make two
/// nameless devices collide.
BeamTarget? readTarget(Map<String, Object?> body, {required String host}) {
  final Object? fingerprint = body['fingerprint'];
  if (fingerprint is! String || fingerprint.isEmpty) return null;
  final Object? port = body['port'];
  return BeamTarget(
    alias: body['alias'] as String? ?? host,
    host: host,
    port: port is int ? port : LocalSendIdentity.defaultPort,
    fingerprint: fingerprint,
    // Absent means http: the field is optional in v2, and guessing https
    // would make every plain receiver unreachable behind a TLS handshake.
    usesHttps: body['protocol'] == 'https',
    kind: BeamDeviceKind.fromWireName(body['deviceType'] as String?),
    model: body['deviceModel'] as String?,
  );
}

/// Builds the `files` map `/prepare-upload` expects.
///
/// A **map keyed by file id**, not a list — v2 changed this from v1, and a
/// list is silently rejected by a v2 receiver.
///
/// No `sha256` and no `preview`: both are optional, and both cost real work
/// per file (a full read to hash, a decode to preview) for something the
/// receiver only uses to verify or to draw a thumbnail it will have in a
/// moment anyway. A phone sending forty wallpapers should not read all of them
/// twice.
Map<String, Object?> prepareUploadFiles(List<BeamFile> files) {
  return <String, Object?>{
    for (final BeamFile file in files)
      file.id: <String, Object?>{
        'id': file.id,
        'fileName': file.fileName,
        'size': file.sizeBytes,
        'fileType': file.mimeType,
      },
  };
}
