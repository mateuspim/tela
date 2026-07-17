import 'package:flutter/services.dart';
import 'package:tela/domain/models/wallpaper_adjust_failure.dart';
import 'package:tela/domain/ports/system_wallpaper_editor.dart';

/// Signature of tela's native adjust method.
typedef InvokeAdjustMethod =
    Future<Object?> Function(String method, Map<String, String> arguments);

/// [SystemWallpaperEditor] backed by tela's Android method channel.
///
/// The Kotlin side downloads the source into app cache, exposes it through the
/// same `FileProvider` the share sheet uses, and launches Android's
/// `ACTION_CROP_AND_SET_WALLPAPER` on it. Success here means the editor opened,
/// not that a wallpaper was set — that outcome belongs to the editor, and tela
/// never hears it.
///
/// Shares the `cc.pym.tela/wallpaper` channel with the applier: both are the
/// wallpaper surface, and a second channel would only be a second name for the
/// same seam.
class MethodChannelSystemWallpaperEditor implements SystemWallpaperEditor {
  /// Creates the adapter.
  ///
  /// [invokeMethod] is injectable so tests never invoke a platform channel.
  MethodChannelSystemWallpaperEditor({InvokeAdjustMethod? invokeMethod})
    : _invokeMethod = invokeMethod ?? _invokeNativeMethod;

  final InvokeAdjustMethod _invokeMethod;

  static const MethodChannel _channel = MethodChannel('cc.pym.tela/wallpaper');

  @override
  Future<void> openFor({required Uri source, required String fileName}) async {
    try {
      final Object? raw = await _invokeMethod(
        'adjustWallpaper',
        <String, String>{'source': source.toString(), 'fileName': fileName},
      );
      final WallpaperAdjustFailure? failure = _failureFrom(raw);
      if (failure != null) throw failure;
    } on PlatformException catch (error) {
      throw WallpaperAdjustFailure(_problemFor(error.code));
    }
  }

  static Future<Object?> _invokeNativeMethod(
    String method,
    Map<String, String> arguments,
  ) {
    return _channel.invokeMethod<Object?>(method, arguments);
  }

  WallpaperAdjustFailure? _failureFrom(Object? raw) {
    if (raw is Map<Object?, Object?> && raw['success'] == true) return null;
    final Object? code = raw is Map<Object?, Object?> ? raw['errorCode'] : null;
    return WallpaperAdjustFailure(_problemFor(code));
  }

  WallpaperAdjustProblem _problemFor(Object? code) {
    return switch (code) {
      'downloadFailed' => WallpaperAdjustProblem.source,
      'noEditor' => WallpaperAdjustProblem.unavailable,
      'unsupportedImage' => WallpaperAdjustProblem.unsupportedImage,
      _ => WallpaperAdjustProblem.unknown,
    };
  }
}
