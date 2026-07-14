import 'package:flutter/services.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/ports/wallpaper_applier.dart';

/// Signature of tela's native wallpaper method.
typedef InvokeWallpaperMethod =
    Future<Object?> Function(String method, Map<String, String> arguments);

/// [WallpaperApplier] backed by tela's Android method channel.
///
/// The Kotlin side downloads into app-private cache and calls Android's public
/// wallpaper API. No storage permission or third-party plugin is involved.
class MethodChannelWallpaperApplier implements WallpaperApplier {
  /// Creates the adapter.
  ///
  /// [invokeMethod] is injectable so tests never invoke a platform channel.
  MethodChannelWallpaperApplier({InvokeWallpaperMethod? invokeMethod})
    : _invokeMethod = invokeMethod ?? _invokeNativeMethod;

  final InvokeWallpaperMethod _invokeMethod;

  static const MethodChannel _channel = MethodChannel(
    'cc.pym.tela/wallpaper',
  );

  @override
  Future<void> apply({
    required String imageUrl,
    required WallpaperTarget target,
  }) async {
    try {
      final Object? raw = await _invokeMethod(
        'applyWallpaper',
        <String, String>{
          'imageUrl': imageUrl,
          'target': target.name,
        },
      );
      final WallpaperApplyFailure? failure = _failureFrom(raw);
      if (failure != null) throw failure;
    } on PlatformException catch (error) {
      throw WallpaperApplyFailure(_problemFor(error.code));
    }
  }

  static Future<Object?> _invokeNativeMethod(
    String method,
    Map<String, String> arguments,
  ) {
    return _channel.invokeMethod<Object?>(method, arguments);
  }

  WallpaperApplyFailure? _failureFrom(Object? raw) {
    if (raw is Map<Object?, Object?> && raw['success'] == true) return null;
    final Object? code = raw is Map<Object?, Object?> ? raw['errorCode'] : null;
    return WallpaperApplyFailure(_problemFor(code));
  }

  WallpaperApplyProblem _problemFor(Object? code) {
    return switch (code) {
      'downloadFailed' => WallpaperApplyProblem.source,
      'unsupported' => WallpaperApplyProblem.unsupported,
      'applyFailed' => WallpaperApplyProblem.rejected,
      _ => WallpaperApplyProblem.unknown,
    };
  }
}
