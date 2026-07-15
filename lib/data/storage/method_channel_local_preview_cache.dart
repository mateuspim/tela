import 'package:flutter/services.dart';
import 'package:tela/domain/models/local_preview.dart';
import 'package:tela/domain/ports/local_preview_cache.dart';

/// Signature of tela's native image method, shared with the image store.
typedef InvokePreviewMethod =
    Future<Object?> Function(String method, Map<String, String> arguments);

/// [LocalPreviewCache] backed by tela's native Android image adapter.
///
/// A plain `file:` location is resolved in Dart and never crosses the channel:
/// it is already a path `FileImage` can read, and materialising it natively
/// would only risk copying a file the user downloaded. A `content:` or SAF
/// document URI is handed to native code, which copies it into an app cache
/// file — the only place Flutter can decode it from — and answers with the
/// throwaway path.
class MethodChannelLocalPreviewCache implements LocalPreviewCache {
  /// Creates an adapter whose native invocation can be replaced in tests.
  MethodChannelLocalPreviewCache({InvokePreviewMethod? invokeMethod})
    : _invokeMethod = invokeMethod ?? _invokeNativeMethod;

  final InvokePreviewMethod _invokeMethod;

  static const MethodChannel _channel = MethodChannel('cc.pym.tela/images');

  @override
  Future<LocalPreview?> materialize(Uri location) async {
    if (location.scheme == 'file') {
      return LocalPreview(path: location.toFilePath(), isTemporary: false);
    }
    try {
      final Object? raw = await _invokeMethod(
        'materializeImage',
        <String, String>{
          'location': location.toString(),
        },
      );
      return _previewFrom(raw);
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> release(LocalPreview preview) async {
    if (!preview.isTemporary) return;
    try {
      await _invokeMethod('releasePreview', <String, String>{
        'path': preview.path,
      });
    } on PlatformException {
      // A preview that cannot be deleted is a leaked cache file, not a user
      // problem: the cache directory is Android's to reclaim. Never surfaced.
    }
  }

  static Future<Object?> _invokeNativeMethod(
    String method,
    Map<String, String> arguments,
  ) {
    return _channel.invokeMethod<Object?>(method, arguments);
  }

  LocalPreview? _previewFrom(Object? raw) {
    if (raw is! Map<Object?, Object?> || raw['success'] != true) return null;
    final Object? path = raw['path'];
    if (path is! String) return null;
    return LocalPreview(path: path, isTemporary: true);
  }
}
