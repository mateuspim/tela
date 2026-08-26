import 'package:flutter/services.dart';
import 'package:tela/domain/ports/notification_access.dart';

/// Signature of tela's native notification-settings method.
typedef InvokeNotificationMethod = Future<Object?> Function(String method);

/// [NotificationAccess] backed by Android's own notification settings.
///
/// Both answers fail closed, and they fail closed in opposite directions for
/// the same reason — never claim more than is known. An unanswerable "are they
/// on?" reads as **off**, so the row offers the way to fix it rather than
/// asserting all is well; an unanswerable "did it open?" reads as **not
/// opened**, so the screen can say so instead of leaving the user waiting for
/// a page that never came.
class MethodChannelNotificationAccess implements NotificationAccess {
  /// Creates an adapter whose native invocation can be replaced in tests.
  MethodChannelNotificationAccess({InvokeNotificationMethod? invokeMethod})
    : _invokeMethod = invokeMethod ?? _invokeNativeMethod;

  final InvokeNotificationMethod _invokeMethod;

  static const MethodChannel _channel = MethodChannel(
    'cc.pym.tela/notifications',
  );

  @override
  Future<bool> areEnabled() => _flag('areEnabled', 'enabled');

  @override
  Future<bool> openSettings() => _flag('openSettings', 'opened');

  /// Reads one boolean off a native answer, false for anything unexpected.
  Future<bool> _flag(String method, String key) async {
    try {
      final Object? raw = await _invokeMethod(method);
      return raw is Map<Object?, Object?> && raw[key] == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // No activity attached — the channel lives on the screen. The row simply
      // reports off rather than taking the settings page down with it.
      return false;
    }
  }

  static Future<Object?> _invokeNativeMethod(String method) {
    return _channel.invokeMethod<Object?>(method);
  }
}
