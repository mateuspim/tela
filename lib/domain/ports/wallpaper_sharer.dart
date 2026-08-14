import 'package:tela/domain/models/clipboard_confirmation.dart';
import 'package:tela/domain/models/wallpaper_share_failure.dart';

/// Hands a wallpaper to another app — through Android's share sheet, or by
/// leaving it on the clipboard for the other app to paste.
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

  /// Fetches [source] and puts the image file on the system clipboard under
  /// [fileName], so any app can paste it without a chooser in between.
  ///
  /// Returns who confirmed the copy to the user, since the platform does it
  /// itself from Android 13 (see [ClipboardConfirmation]). Unlike [shareImage]
  /// this accepts an explicit wallpaper — see `shareOptionsFor` for that
  /// decision — and such a copy passes `sensitive: true`, which implementations
  /// must carry to the platform so the system's clipboard preview shows a
  /// placeholder instead of the picture. Throws [WallpaperShareFailure] and
  /// never includes [source] in the thrown value.
  Future<ClipboardConfirmation> copyImage({
    required Uri source,
    required String fileName,
    required bool sensitive,
  });
}
