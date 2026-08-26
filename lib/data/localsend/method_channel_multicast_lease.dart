import 'package:flutter/services.dart';
import 'package:tela/domain/ports/multicast_lease.dart';

/// [MulticastLease] over the native `MulticastLease` object.
///
/// The whole beam protocol is plain Dart; this is the one piece that cannot
/// be, because only the platform can tell its Wi-Fi stack to stop discarding
/// the packets discovery listens for.
class MethodChannelMulticastLease implements MulticastLease {
  /// Creates the adapter over the beam channel.
  const MethodChannelMulticastLease([
    this._channel = const MethodChannel('cc.pym.tela/beam'),
  ]);

  final MethodChannel _channel;

  @override
  Future<bool> acquire() async {
    try {
      return await _channel.invokeMethod<bool>('acquireMulticastLock') ?? false;
    } on PlatformException {
      // A platform that cannot hold the lock still lets discovery run; it will
      // simply find nothing, which is the same observation as a quiet network
      // and is what `sendTo` exists for. Failing the whole beam over it would
      // be worse than finding nothing.
      return false;
    } on MissingPluginException {
      // Non-Android, or a test binding with no handler registered.
      return false;
    }
  }

  @override
  Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('releaseMulticastLock');
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }
}
