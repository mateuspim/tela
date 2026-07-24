import 'package:meta/meta.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/search_tag.dart';
import 'package:tela/domain/models/wallpaper_color.dart';
import 'package:tela/domain/models/wallpaper_details.dart';

/// Somewhere a wallpaper points at: one of the things tela prints on a detail
/// screen that lead to a listing of their own — a tag, an uploader, a colour.
///
/// A link is deliberately *not* a query. It names only what the user asked to
/// see and knows how to [narrow] a query down to it, layering itself over the
/// filters they are already browsing under (their purity, categories, ratio)
/// and the resolution of the device in their hand. So following one costs a
/// search and nothing else, and never widens a filter the user set.
///
/// ```dart
/// const TagLink(WallpaperTag(id: 37, name: 'nature')).narrow(query).term;
/// // 'id:37'
/// ```
@immutable
sealed class WallpaperLink {
  /// Creates a link.
  const WallpaperLink();

  /// Narrows [query] to this link's listing, keeping the filters already on it.
  ///
  /// Always newest-first. A tag or uploader replaces the search term with its
  /// `q` operator — sent alone, because `id:`/`@` return nothing when combined
  /// with other `q` text. A colour sets the colour filter and clears the term.
  /// Everything else on [query] is the user's and is left untouched.
  SearchQuery narrow(SearchQuery query);
}

/// Every wallpaper carrying one exact tag.
@immutable
final class TagLink extends WallpaperLink {
  /// Creates a link to [tag]'s listing.
  const TagLink(this.tag);

  /// The tag followed, carried whole so the screen can title itself with the
  /// name while the query searches on the id.
  final WallpaperTag tag;

  /// `id:{n}`, Wallhaven's **exact**-tag operator — not `+{name}`, which is a
  /// fuzzy text match that would quietly return a *different* tag reading the
  /// same. Sent alone, as `id:` demands.
  ///
  /// A tag with no id narrows by name instead, and loses nothing by it: only a
  /// source whose tag names *are* the identifier hands over an id-less tag
  /// (PLAN §18.4), so there is no fuzzier match to fall into.
  @override
  SearchQuery narrow(SearchQuery query) {
    final int? tagId = tag.id;
    if (tagId == null) {
      return query.copyWith(
        term: '',
        tags: <SearchTag>[SearchTag(tag.name)],
        sorting: Sorting.dateAdded,
      );
    }
    return query.copyWith(term: 'id:$tagId', sorting: Sorting.dateAdded);
  }

  @override
  bool operator ==(Object other) => other is TagLink && other.tag == tag;

  @override
  int get hashCode => Object.hash(TagLink, tag);
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
  SearchQuery narrow(SearchQuery query) =>
      query.copyWith(term: '@$username', sorting: Sorting.dateAdded);

  @override
  bool operator ==(Object other) =>
      other is UploaderLink && other.username == username;

  @override
  int get hashCode => Object.hash(UploaderLink, username);
}

/// Every wallpaper sharing one of a wallpaper's dominant colours.
///
/// The colour is a query *param* (`colors=`), not a `q` operator, so it sets
/// [SearchQuery.color] and clears the term rather than replacing it — "more
/// like this colour", under whatever purity and categories the user was on.
@immutable
final class ColorLink extends WallpaperLink {
  /// Creates a link to [color]'s listing.
  const ColorLink(this.color);

  /// The dominant colour tapped, from Wallhaven's fixed palette.
  final WallpaperColor color;

  @override
  SearchQuery narrow(SearchQuery query) =>
      query.withColor(color).copyWith(term: '', sorting: Sorting.dateAdded);

  @override
  bool operator ==(Object other) => other is ColorLink && other.color == color;

  @override
  int get hashCode => Object.hash(ColorLink, color);
}
