import 'package:tela/domain/models/bitmap_export_rule.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_file_name.dart';
import 'package:tela/domain/ports/system_wallpaper_editor.dart';

/// Opens Android's own crop-and-set editor on a [Wallpaper].
///
/// The optional path beside `ApplyWallpaper`: that one sets the wallpaper
/// directly in as few taps as possible, this one lets the user frame it first
/// on the OEM's own screen. Both exist because a default 9x16 listing on a 9x20
/// phone is always cropped by *something* — the only question is whether the
/// user or the system chose where.
class AdjustWallpaper {
  /// Creates the use case over the platform-independent [editor] port.
  const AdjustWallpaper({required SystemWallpaperEditor editor})
    : _editor = editor;

  final SystemWallpaperEditor _editor;

  /// Opens the system editor on [wallpaper]'s full-resolution image.
  ///
  /// Refused for explicit wallpapers: the editor is a separate app, so its
  /// pixels would leave tela exactly as a shared image file would (see
  /// `mayExportBitmap`). The detail screen already withholds the action for
  /// them; this guard is the domain half of the same rule, enforced here rather
  /// than trusted to the UI that reads it.
  Future<void> call(Wallpaper wallpaper) {
    if (!mayExportBitmap(wallpaper.purity)) {
      throw ArgumentError(
        'an explicit wallpaper may not be opened in the system editor, which '
        'keeps its own wallpaper history; got "${wallpaper.id}"',
      );
    }
    return _editor.openFor(
      source: Uri.parse(wallpaper.fullImageUrl),
      fileName: wallpaperFileName(wallpaper),
    );
  }
}
