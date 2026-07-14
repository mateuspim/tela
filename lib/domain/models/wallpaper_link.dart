import 'package:meta/meta.dart';
import 'package:tela/domain/models/wallpaper_details.dart';

/// Somewhere a wallpaper points at: one of the two things tela prints on a
/// detail screen that lead to a listing of their own.
///
/// A link is deliberately *not* a query. It names only what the user asked to
/// see — a tag, an uploader — and the screen that shows it layers on the
/// filters they are browsing under and the resolution of the device in their
/// hand. Both forms are Wallhaven `q` operators, so following one costs a
/// search and nothing else.
///
/// ```dart
/// const TagLink(WallpaperTag(id: 37, name: 'nature')).term; // 'id:37'
/// ```
@immutable
sealed class WallpaperLink {
  /// Creates a link.
  const WallpaperLink();

  /// The Wallhaven `q` term that searches for this link's listing.
  String get term;
}

/// Every wallpaper carrying one exact tag.
@immutable
final class TagLink extends WallpaperLink {
  /// Creates a link to [tag]'s listing.
  const TagLink(this.tag);

  /// The tag followed, carried whole so the screen can title itself with the
  /// name while the query searches on the id.
  final WallpaperTag tag;

  /// `id:{n}`, which is Wallhaven's **exact**-tag operator.
  ///
  /// Not `+{name}`: that is a fuzzy text match, and it would quietly return
  /// wallpapers carrying a *different* tag whose name merely reads the same.
  @override
  String get term => 'id:${tag.id}';

  @override
  bool operator ==(Object other) => other is TagLink && other.tag.id == tag.id;

  @override
  int get hashCode => Object.hash(TagLink, tag.id);
}

/// Everything one Wallhaven user has uploaded.
///
/// Not a profile, and the screen says so: **Wallhaven's API has no user
/// endpoint**. Their uploads, their avatar, and their group are all it can ever
/// know about them, and the first of those is this listing.
@immutable
final class UploaderLink extends WallpaperLink {
  /// Creates a link to [username]'s uploads.
  const UploaderLink(this.username);

  /// The uploader's public Wallhaven name, without the `@`.
  final String username;

  /// `@{username}`, Wallhaven's uploader operator.
  @override
  String get term => '@$username';

  @override
  bool operator ==(Object other) =>
      other is UploaderLink && other.username == username;

  @override
  int get hashCode => Object.hash(UploaderLink, username);
}
