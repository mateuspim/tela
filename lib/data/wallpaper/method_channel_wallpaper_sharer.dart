import 'package:flutter/services.dart';
import 'package:tela/domain/models/wallpaper_share_failure.dart';
import 'package:tela/domain/ports/wallpaper_sharer.dart';

/// Signature of tela's native share method.
typedef InvokeShareMethod =
    Future<Object?> Function(String method, Map<String, String> arguments);

/// [WallpaperSharer] backed by tela's Android method channel.
///
/// The Kotlin side launches an `ACTION_SEND` chooser. For a link it sends the
/// URL as text; for an image it downloads the source into app cache, exposes it
/// through a `FileProvider`, and grants the receiver read access — no storage
/// permission or third-party plugin is involved.
class MethodChannelWallpaperSharer implements WallpaperSharer {
  /// Creates the adapter.
  ///
  /// [invokeMethod] is injectable so tests never invoke a platform channel.
  MethodChannelWallpaperSharer({InvokeShareMethod? invokeMethod})
    : _invokeMethod = invokeMethod ?? _invokeNativeMethod;

  final InvokeShareMethod _invokeMethod;

  static const MethodChannel _channel = MethodChannel('cc.pym.tela/share');

  @override
  Future<void> shareLink(Uri page) {
    return _invoke('shareLink', <String, String>{'page': page.toString()});
  }

  @override
  Future<void> shareImage({required Uri source, required String fileName}) {
    return _invoke('shareImage', <String, String>{
      'source': source.toString(),
      'fileName': fileName,
    });
  }

  Future<void> _invoke(String method, Map<String, String> arguments) async {
    try {
      final Object? raw = await _invokeMethod(method, arguments);
      final WallpaperShareFailure? failure = _failureFrom(raw);
      if (failure != null) throw failure;
    } on PlatformException catch (error) {
      throw WallpaperShareFailure(_problemFor(error.code));
    }
  }

  static Future<Object?> _invokeNativeMethod(
    String method,
    Map<String, String> arguments,
  ) {
    return _channel.invokeMethod<Object?>(method, arguments);
  }

  WallpaperShareFailure? _failureFrom(Object? raw) {
    if (raw is Map<Object?, Object?> && raw['success'] == true) return null;
    final Object? code = raw is Map<Object?, Object?> ? raw['errorCode'] : null;
    return WallpaperShareFailure(_problemFor(code));
  }

  WallpaperShareProblem _problemFor(Object? code) {
    return switch (code) {
      'downloadFailed' => WallpaperShareProblem.source,
      'noTarget' => WallpaperShareProblem.unavailable,
      _ => WallpaperShareProblem.unknown,
    };
  }
}
