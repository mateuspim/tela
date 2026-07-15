import 'package:tela/domain/models/wallpaper_share_failure.dart';

/// Hands a wallpaper to another app through Android's share sheet.
///
/// Implementations own the platform intent — launching the chooser and, for an
/// image, fetching the bytes and exposing them to the receiving app. Features
/// never build a share intent directly.
abstract interface class WallpaperSharer {
  /// Shares [page] — a wallpaper's public Wallhaven URL — as plain text.
  ///
  /// Throws [WallpaperShareFailure] when no app can receive it; never includes
  /// [page] in the thrown value.
  Future<void> shareLink(Uri page);

  /// Fetches [source] and shares the image file, suggesting [fileName] to the
  /// receiving app so it keeps a sensible name and extension.
  ///
  /// Callers must not pass an explicit wallpaper here — exporting its bytes is
  /// refused in the domain (see `ShareWallpaper.image`). Throws
  /// [WallpaperShareFailure] and never includes [source] in the thrown value.
  Future<void> shareImage({required Uri source, required String fileName});
}
