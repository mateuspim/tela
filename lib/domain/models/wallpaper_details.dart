import 'package:meta/meta.dart';
import 'package:tela/domain/models/wallpaper.dart';

/// The detail-only information Wallhaven supplies for one [wallpaper].
///
/// The browse grid deliberately carries only [Wallpaper]. This model keeps
/// larger, one-screen metadata out of every paginated result while making the
/// detail view's data contract entirely non-nullable.
@immutable
class WallpaperDetails {
  /// Creates fully populated metadata for a wallpaper.
  const WallpaperDetails({
    required this.wallpaper,
    required this.ratio,
    required this.fileType,
    required this.tags,
    required this.uploader,
    required this.source,
    required this.views,
    required this.favorites,
  });

  /// The common image fields also used by browse and wallpaper apply.
  final Wallpaper wallpaper;

  /// Width-to-height ratio as supplied by Wallhaven, such as `"1.78"`.
  final String ratio;

  /// MIME type of the source image, such as `"image/jpeg"`.
  final String fileType;

  /// Labels assigned to the wallpaper, in Wallhaven's displayed order.
  final List<WallpaperTag> tags;

  /// The user who uploaded the wallpaper.
  final WallpaperUploader uploader;

  /// The credited source URL, or an empty string when none was provided.
  final String source;

  /// Number of Wallhaven detail-page views at fetch time.
  final int views;

  /// Number of Wallhaven favorites at fetch time.
  final int favorites;
}

/// One Wallhaven tag displayed with a wallpaper.
@immutable
class WallpaperTag {
  /// Creates a tag with its stable Wallhaven id and display name.
  const WallpaperTag({required this.id, required this.name});

  /// Wallhaven's numeric tag id.
  final int id;

  /// Human-readable tag label.
  final String name;
}

/// The Wallhaven user credited as a wallpaper's uploader.
@immutable
class WallpaperUploader {
  /// Creates uploader information supplied by the detail endpoint.
  const WallpaperUploader({
    required this.username,
    required this.group,
    required this.avatarUrl,
  });

  /// The uploader's public Wallhaven name.
  final String username;

  /// Wallhaven's uploader group, or an empty string for no group.
  final String group;

  /// Avatar URL, or an empty string when Wallhaven did not provide one.
  final String avatarUrl;
}
