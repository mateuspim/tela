import 'package:tela/domain/models/clipboard_confirmation.dart';
import 'package:tela/domain/models/share_option.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_file_name.dart';
import 'package:tela/domain/ports/wallpaper_sharer.dart';

/// Shares a [Wallpaper] out through Android's share sheet or the clipboard.
class ShareWallpaper {
  /// Creates the use case over the platform-independent [sharer] port.
  const ShareWallpaper({required WallpaperSharer sharer}) : _sharer = sharer;

  final WallpaperSharer _sharer;

  /// Shares the wallpaper's public source page. Allowed for any purity — the
  /// page is public, so the link reveals nothing tela is holding back.
  Future<void> link(Wallpaper wallpaper) {
    return _sharer.shareLink(wallpaper.pageUrl);
  }

  /// Shares the full-resolution image file itself.
  ///
  /// Refused for an explicit wallpaper: the receiving app keeps the file, which
  /// is the hand-off `mayExportBitmap` exists to stop. The clipboard makes the
  /// opposite call — see [clipboard] and [shareOptionsFor].
  Future<void> image(Wallpaper wallpaper) {
    _refuseExplicitExport(wallpaper, ShareOption.image);
    return _sharer.shareImage(
      source: Uri.parse(wallpaper.fullImageUrl),
      fileName: wallpaperFileName(wallpaper),
    );
  }

  /// Puts the full-resolution image on the system clipboard, for pasting into
  /// another app directly. Reports who confirmed it to the user.
  ///
  /// Allowed at every purity ([shareOptionsFor] explains the decision and what
  /// it costs). An explicit wallpaper travels marked **sensitive** — the one
  /// thing tela still controls once the bytes are on the clipboard, since the
  /// system's own preview then shows a placeholder instead of the picture.
  Future<ClipboardConfirmation> clipboard(Wallpaper wallpaper) {
    return _sharer.copyImage(
      source: Uri.parse(wallpaper.fullImageUrl),
      fileName: wallpaperFileName(wallpaper),
      sensitive: wallpaper.isNsfw,
    );
  }

  /// Refuses [option] for an explicit wallpaper, exporting its bitmap *as a
  /// file* being the thing the NSFW rules forbid (see [shareOptionsFor]).
  ///
  /// The menu already withholds the option, so this is the domain half of the
  /// same rule — the invariant is enforced here, not only in the UI that reads
  /// it. It takes the option rather than assuming one, so a future export route
  /// joins the guard instead of going around it.
  void _refuseExplicitExport(Wallpaper wallpaper, ShareOption option) {
    if (shareOptionsFor(wallpaper.purity).contains(option)) return;
    throw ArgumentError(
      'only the link may be shared for an explicit wallpaper, not '
      '${option.name}; got "${wallpaper.id}"',
    );
  }
}
