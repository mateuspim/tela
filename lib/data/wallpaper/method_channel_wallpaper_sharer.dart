import 'package:flutter/services.dart';
import 'package:tela/domain/models/clipboard_confirmation.dart';
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
/// permission or third-party plugin is involved. A clipboard copy takes the
/// same cached file and hands its content URI to `ClipboardManager` instead of
/// to a chooser, flagging the clip sensitive when the wallpaper is explicit.
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

  @override
  Future<ClipboardConfirmation> copyImage({
    required Uri source,
    required String fileName,
    required bool sensitive,
  }) async {
    final Object? raw = await _invoke('copyImage', <String, String>{
      'source': source.toString(),
      'fileName': fileName,
      // As a string like every other argument on this channel: the native side
      // reads it back as one, so a silent type change cannot flip a sensitive
      // copy into an ordinary one.
      'sensitive': sensitive.toString(),
    });
    return _confirmationFrom(raw);
  }

  /// Runs [method] and returns its raw response, throwing the domain failure
  /// when the native side reports one.
  Future<Object?> _invoke(String method, Map<String, String> arguments) async {
    try {
      final Object? raw = await _invokeMethod(method, arguments);
      final WallpaperShareFailure? failure = _failureFrom(raw);
      if (failure != null) throw failure;
      return raw;
    } on PlatformException catch (error) {
      throw WallpaperShareFailure(_problemFor(error.code));
    }
  }

  /// Reads which side confirmed the copy. Absent means tela owes it: an older
  /// Android shows nothing, and so does a native response tela cannot read.
  ClipboardConfirmation _confirmationFrom(Object? raw) {
    final bool systemShown =
        raw is Map<Object?, Object?> && raw['systemNotice'] == true;
    return systemShown
        ? ClipboardConfirmation.system
        : ClipboardConfirmation.tela;
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
