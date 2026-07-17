import 'package:flutter/services.dart';
import 'package:tela/domain/models/crop_region.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/ports/wallpaper_applier.dart';

/// Signature of tela's native wallpaper method.
typedef InvokeWallpaperMethod =
    Future<Object?> Function(String method, Map<String, String> arguments);

/// [WallpaperApplier] backed by tela's Android method channel.
///
/// The Kotlin side reads the source — over HTTP, or from the local file a past
/// download left behind — into app-private cache, then calls Android's public
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
    required Uri source,
    required WallpaperTarget target,
  }) async {
    try {
      final Object? raw = await _invokeMethod(
        'applyWallpaper',
        <String, String>{
          'source': source.toString(),
          'target': target.name,
        },
      );
      final WallpaperApplyFailure? failure = _failureFrom(raw);
      if (failure != null) throw failure;
    } on PlatformException catch (error) {
      throw WallpaperApplyFailure(_problemFor(error.code));
    }
  }

  @override
  Future<void> applyRegion({
    required Uri source,
    required WallpaperTarget target,
    required CropRegion region,
  }) async {
    try {
      final Object? raw = await _invokeMethod(
        'applyCroppedWallpaper',
        <String, String>{
          'source': source.toString(),
          'target': target.name,
          'left': region.left.toString(),
          'top': region.top.toString(),
          'width': region.width.toString(),
          'height': region.height.toString(),
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

  /// A source that could not be *downloaded* and one that could not be *read*
  /// from disk are one problem to a caller: the image is gone. `ApplyDownload`
  /// leans on that to decide it should fall back to Wallhaven.
  WallpaperApplyProblem _problemFor(Object? code) {
    return switch (code) {
      'downloadFailed' => WallpaperApplyProblem.source,
      'sourceUnreadable' => WallpaperApplyProblem.source,
      'unsupported' => WallpaperApplyProblem.unsupported,
      'applyFailed' => WallpaperApplyProblem.rejected,
      _ => WallpaperApplyProblem.unknown,
    };
  }
}
