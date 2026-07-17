import 'package:tela/domain/models/share_option.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_file_name.dart';
import 'package:tela/domain/ports/wallpaper_sharer.dart';

/// Shares a [Wallpaper] out through Android's share sheet, as a link or a file.
class ShareWallpaper {
  /// Creates the use case over the platform-independent [sharer] port.
  const ShareWallpaper({required WallpaperSharer sharer}) : _sharer = sharer;

  final WallpaperSharer _sharer;

  /// Shares the wallpaper's public Wallhaven page. Allowed for any purity — the
  /// page is public, so the link reveals nothing tela is holding back.
  Future<void> link(Wallpaper wallpaper) {
    return _sharer.shareLink(wallpaper.pageUrl);
  }

  /// Shares the full-resolution image file itself.
  ///
  /// Refused for explicit wallpapers: exporting the bitmap collides with the
  /// NSFW rules (see [shareOptionsFor]). The share menu already withholds the
  /// option for them, so this guard is the domain half of the same rule — the
  /// invariant is enforced here, not only in the UI that reads it.
  Future<void> image(Wallpaper wallpaper) {
    if (!shareOptionsFor(wallpaper.purity).contains(ShareOption.image)) {
      throw ArgumentError(
        'only the link may be shared for an explicit wallpaper, not the image '
        'file; got "${wallpaper.id}"',
      );
    }
    return _sharer.shareImage(
      source: Uri.parse(wallpaper.fullImageUrl),
      fileName: wallpaperFileName(wallpaper),
    );
  }
}
