import 'package:tela/domain/models/wallpaper.dart';

/// The file name to suggest when handing [wallpaper]'s image to another app.
///
/// Composed from [Wallpaper.ref] — `wallhaven-e7jvjd`, `konachan-406484` — with
/// the extension taken from the image URL rather than guessed, so the real type
/// (`.png` vs `.jpg`) reaches the receiving app, which believes it.
///
/// Composed rather than lifted whole from the URL's last segment, even though
/// Wallhaven's own files are already named exactly this: a booru names its
/// files after the *tags* on the image, which would put an explicit tag list in
/// a file name tela hands to another app.
///
/// Shared by every hand-off that names a file — the share sheet and the system
/// wallpaper editor — because they want the identical name and a second copy
/// would be free to rot.
///
/// ```dart
/// wallpaperFileName(wallpaper); // 'wallhaven-e7jvjd.jpg'
/// ```
String wallpaperFileName(Wallpaper wallpaper) {
  return '${wallpaper.ref.key}${_extensionOf(wallpaper.fullImageUrl)}';
}

/// The `.ext` of [url]'s last path segment, or an empty string when it has
/// none — an extensionless name beats a wrong one.
String _extensionOf(String url) {
  final List<String> segments = Uri.parse(url).pathSegments;
  final String last = segments.isEmpty ? '' : segments.last;
  final int dot = last.lastIndexOf('.');
  if (dot <= 0) return '';
  return last.substring(dot);
}
