import 'package:flutter/services.dart';
import 'package:tela/domain/ports/download_queue_anchor.dart';

/// Signature of tela's native queue-anchor methods.
typedef InvokeQueueAnchorMethod =
    Future<bool?> Function(String method, Map<String, String> arguments);

/// [DownloadQueueAnchor] backed by an Android foreground service.
///
/// Like `MethodChannelScreenGuard`, it only crosses the channel on an actual
/// edge — but for a different reason, and a stronger one. The queue republishes
/// after every settled entry, so an unfiltered adapter would re-post the
/// notification several times a second during a batch; the shade would flicker
/// and the service would be told to start over and over for no change. Here the
/// filter is on the *words*, not on a count, because identical words are
/// exactly what "nothing to tell the user" means.
///
/// A refused hold is deliberately **not** remembered, so the next entry to
/// settle tries again: the refusal is Android's background-start restriction,
/// which lifts the moment the user comes back to the app.
class MethodChannelDownloadQueueAnchor implements DownloadQueueAnchor {
  /// Creates an adapter whose native invocation can be replaced in tests.
  MethodChannelDownloadQueueAnchor({InvokeQueueAnchorMethod? invokeMethod})
    : _invokeMethod = invokeMethod ?? _invokeNativeMethod;

  final InvokeQueueAnchorMethod _invokeMethod;

  /// The notification currently posted, or null when nothing is anchored.
  String? _showing;

  static const MethodChannel _channel = MethodChannel(
    'cc.pym.tela/download_queue',
  );

  @override
  Future<bool> hold({required String title, required String body}) async {
    final String words = '$title\n$body';
    if (_showing == words) return true;
    final bool held =
        await _invokeMethod('anchor', <String, String>{
          'title': title,
          'body': body,
        }) ??
        false;
    _showing = held ? words : null;
    return held;
  }

  @override
  Future<void> release() async {
    if (_showing == null) return;
    _showing = null;
    await _invokeMethod('release', const <String, String>{});
  }

  static Future<bool?> _invokeNativeMethod(
    String method,
    Map<String, String> arguments,
  ) {
    return _channel.invokeMethod<bool>(method, arguments);
  }
}
