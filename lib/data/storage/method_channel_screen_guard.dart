import 'package:flutter/services.dart';
import 'package:tela/domain/ports/screen_guard.dart';

/// Signature of tela's native screen-protection method.
typedef InvokeScreenGuardMethod =
    Future<void> Function(String method, Map<String, bool> arguments);

/// [ScreenGuard] backed by Android's `FLAG_SECURE` on the app window.
///
/// The flag is a property of the *window*, not of a route, so it is turned on
/// when the private library opens and off when it closes. Leaving it on would
/// silently block screenshots of the whole app; never turning it on would leave
/// an explicit wallpaper sitting in the app-switcher thumbnail.
class MethodChannelScreenGuard implements ScreenGuard {
  /// Creates an adapter whose native invocation can be replaced in tests.
  MethodChannelScreenGuard({InvokeScreenGuardMethod? invokeMethod})
    : _invokeMethod = invokeMethod ?? _invokeNativeMethod;

  final InvokeScreenGuardMethod _invokeMethod;

  static const MethodChannel _channel = MethodChannel('cc.pym.tela/screen');

  @override
  Future<void> setSecure({required bool secure}) {
    return _invokeMethod('setSecure', <String, bool>{'secure': secure});
  }

  static Future<void> _invokeNativeMethod(
    String method,
    Map<String, bool> arguments,
  ) {
    return _channel.invokeMethod<void>(method, arguments);
  }
}
