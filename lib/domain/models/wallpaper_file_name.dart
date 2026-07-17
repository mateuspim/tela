import 'package:tela/domain/models/wallpaper.dart';

/// The file name to suggest when handing [wallpaper]'s image to another app.
///
/// Taken from the image URL rather than composed, so the extension matches the
/// real type (`.jpg` vs `.png`) instead of guessing. Falls back to the id when
/// the URL carries no usable last segment, which keeps the name unique and
/// still recognisably Wallhaven's.
///
/// Shared by every hand-off that names a file — the share sheet and the system
/// wallpaper editor — because they want the identical name and a second copy
/// would be free to rot.
///
/// ```dart
/// wallpaperFileName(wallpaper); // 'wallhaven-e7jvjd.jpg'
/// ```
String wallpaperFileName(Wallpaper wallpaper) {
  final Uri image = Uri.parse(wallpaper.fullImageUrl);
  if (image.pathSegments.isEmpty || image.pathSegments.last.isEmpty) {
    return 'wallhaven-${wallpaper.id}';
  }
  return image.pathSegments.last;
}
