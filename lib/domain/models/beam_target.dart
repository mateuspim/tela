import 'package:meta/meta.dart';

/// What kind of machine is on the other end, as LocalSend names them.
///
/// Carried only so a chooser can draw the right icon beside an alias — tela
/// treats every target identically. An unrecognised name from a future
/// protocol version reads as [unknown] rather than throwing: a device tela
/// cannot categorise is still a device it can send to.
enum BeamDeviceKind {
  /// A phone or tablet.
  mobile,

  /// A laptop or workstation — the case this feature exists for.
  desktop,

  /// LocalSend's browser client.
  web,

  /// A machine with no interactive session.
  headless,

  /// A always-on receiver.
  server,

  /// Something this build has no name for.
  unknown;

  /// Reads LocalSend's `deviceType`, never throwing.
  ///
  /// ```dart
  /// BeamDeviceKind.fromWireName('desktop'); // BeamDeviceKind.desktop
  /// ```
  static BeamDeviceKind fromWireName(String? raw) {
    return BeamDeviceKind.values
            .where((BeamDeviceKind kind) => kind.name == raw)
            .firstOrNull ??
        BeamDeviceKind.unknown;
  }
}

/// One machine tela can beam wallpapers to.
///
/// Discovered on the local network, or entered by hand when multicast does not
/// survive the network in between — a guest VLAN, a router with multicast
/// filtering, a phone on cellular. Both routes produce this same value, so
/// nothing downstream knows which one found it.
///
/// [fingerprint] is the protocol's own identity for a device — a certificate
/// hash under `https`, a random string under `http`. It is what distinguishes
/// two machines sharing an alias, and what lets a re-announcement replace a
/// target rather than duplicate it.
///
/// ```dart
/// const BeamTarget(
///   alias: 'workstation',
///   host: '192.168.50.20',
///   port: 53317,
///   fingerprint: 'abc123',
///   usesHttps: true,
///   kind: BeamDeviceKind.desktop,
/// );
/// ```
@immutable
class BeamTarget {
  /// Creates a target.
  const BeamTarget({
    required this.alias,
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.usesHttps,
    this.kind = BeamDeviceKind.unknown,
    this.model,
  });

  /// The name the receiver calls itself — "Nice Orange", a hostname.
  final String alias;

  /// Its address on the local network.
  final String host;

  /// The port its HTTP server listens on. LocalSend's default is 53317.
  final int port;

  /// The protocol's identity for this device. See the class docstring.
  final String fingerprint;

  /// Whether it speaks `https`. LocalSend's desktop clients default to it,
  /// with a self-signed certificate the sender is expected to accept — see
  /// the adapter, which is the only place that may decide to.
  final bool usesHttps;

  /// What kind of machine it says it is.
  final BeamDeviceKind kind;

  /// Its self-reported model — "Windows", "Samsung". Null when it sends none.
  final String? model;

  /// The base URL every request to this target is built on.
  String get baseUrl => '${usesHttps ? 'https' : 'http'}://$host:$port';

  /// Identity is the fingerprint, not the address.
  ///
  /// A machine that changes address on a DHCP lease is the same machine, and a
  /// discovery list keyed on host would show it twice.
  @override
  bool operator ==(Object other) =>
      other is BeamTarget && other.fingerprint == fingerprint;

  @override
  int get hashCode => fingerprint.hashCode;

  @override
  String toString() => '$alias ($host:$port)';
}
