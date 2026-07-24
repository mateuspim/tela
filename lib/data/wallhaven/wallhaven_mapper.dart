import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';

/// Maps Wallhaven's JSON to domain models.
///
/// This is the only place that knows the API's field names. DTOs do not escape
/// `data/` (CLAUDE.md), so there is no DTO *class* here at all — just the
/// mapping, which keeps the boundary impossible to leak across by accident.
///
/// Wallhaven reserves the right to change the API without notice, so every
/// field is read defensively and a bad payload becomes an
/// [UnexpectedResponseFailure] rather than a crashed grid.
abstract final class WallhavenMapper {
  /// Maps a `/search` response body to a page of wallpapers.
  ///
  /// ```dart
  /// final WallpaperPage page = WallhavenMapper.toPage(response.data);
  /// ```
  static WallpaperPage toPage(Map<String, dynamic> body) {
    final Object? data = body['data'];
    if (data is! List) {
      throw UnexpectedResponseFailure(
        'expected "data" to be a list of wallpapers, got ${data.runtimeType}',
      );
    }
    final Map<String, dynamic> meta = _readMeta(body);
    final int currentPage = _readInt(meta, 'current_page', fallback: 1);
    final int lastPage = _readInt(meta, 'last_page', fallback: 1);
    return WallpaperPage(
      wallpapers: data.map(_toWallpaper).toList(),
      currentPage: currentPage,
      // Wallhaven does publish a page count, so `hasMore` is decided here
      // rather than by a short page — the fallback a source without one needs.
      hasMore: currentPage < lastPage,
      lastPage: lastPage,
      seed: meta['seed'] as String?,
    );
  }

  /// Maps a `/w/{id}` response body to non-nullable wallpaper metadata.
  static WallpaperDetails toDetails(Map<String, dynamic> body) {
    final Object? data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw UnexpectedResponseFailure(
        'expected "data" to be a wallpaper object, got ${data.runtimeType}',
      );
    }
    return WallpaperDetails(
      wallpaper: _toWallpaper(data),
      ratio: _readString(data, 'ratio'),
      fileType: _readString(data, 'file_type'),
      tags: _readTags(data),
      uploader: _readUploader(data),
      source: _readOptionalString(data, 'source'),
      views: _readInt(data, 'views', fallback: 0),
      favorites: _readInt(data, 'favorites', fallback: 0),
    );
  }

  /// Maps a `/settings` response body to the account's browse defaults.
  ///
  /// Read softer than the other two on purpose. A wallpaper with no `path` is
  /// useless, but an account setting tela cannot read is merely a *preference*
  /// it cannot honour — so an unknown category name costs that category, an
  /// unreadable range costs the range, and an empty list means the account
  /// never narrowed it and gets tela's own default.
  ///
  /// Three of the body's fields are read by nobody, and the one that matters is
  /// **`purity`**: browse always opens on safe, whatever the account says. See
  /// [AccountSettings], which is also where `resolutions` and `aspect_ratios`
  /// are explained away.
  static AccountSettings toAccountSettings(Map<String, dynamic> body) {
    final Object? data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw UnexpectedResponseFailure(
        'expected "data" to be an account settings object, '
        'got ${data.runtimeType}',
      );
    }
    final Set<Category> categories = _readApiNames(
      data,
      'categories',
      Category.tryFromApiName,
    );
    return AccountSettings(
      categories: categories.isEmpty
          ? CategoryFilter.all
          : CategoryFilter(categories),
      topRange:
          TopRange.tryFromApiValue(
            _readOptionalString(data, 'toplist_range'),
          ) ??
          TopRange.oneMonth,
    );
  }

  /// Reads a list of API names, dropping every entry [tryParse] cannot read.
  static Set<T> _readApiNames<T extends Object>(
    Map<String, dynamic> raw,
    String key,
    T? Function(String name) tryParse,
  ) {
    final Object? names = raw[key];
    if (names is! List) return <T>{};
    return names.whereType<String>().map<T?>(tryParse).nonNulls.toSet();
  }

  /// `/search` always sends `meta`; a listing with zero results still does.
  static Map<String, dynamic> _readMeta(Map<String, dynamic> body) {
    final Object? meta = body['meta'];
    if (meta is Map<String, dynamic>) return meta;
    // A single-wallpaper endpoint has no meta — treat it as one full page.
    return <String, dynamic>{};
  }

  static Wallpaper _toWallpaper(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw UnexpectedResponseFailure(
        'expected a wallpaper object, got ${raw.runtimeType}',
      );
    }
    return Wallpaper(
      id: _readString(raw, 'id'),
      source: SourceId.wallhaven,
      pageUrl: Uri.parse(_readString(raw, 'url')),
      fullImageUrl: _readString(raw, 'path'),
      thumbSmallUrl: _readThumb(raw, 'small'),
      thumbLargeUrl: _readThumb(raw, 'large'),
      thumbOriginalUrl: _readThumb(raw, 'original'),
      resolution: Resolution.parse(_readString(raw, 'resolution')),
      fileSizeBytes: _readInt(raw, 'file_size', fallback: 0),
      purity: Purity.fromApiName(_readString(raw, 'purity')),
      category: Category.fromApiName(_readString(raw, 'category')),
      colors: _readColors(raw),
    );
  }

  static String _readThumb(Map<String, dynamic> raw, String size) {
    final Object? thumbs = raw['thumbs'];
    if (thumbs is! Map<String, dynamic>) {
      throw const UnexpectedResponseFailure(
        'wallpaper is missing its "thumbs" object',
      );
    }
    return _readString(thumbs, size);
  }

  static List<String> _readColors(Map<String, dynamic> raw) {
    final Object? colors = raw['colors'];
    if (colors is! List) return const <String>[];
    return colors.whereType<String>().toList();
  }

  static List<WallpaperTag> _readTags(Map<String, dynamic> raw) {
    final Object? tags = raw['tags'];
    if (tags is! List) return const <WallpaperTag>[];
    return tags.map(_toTag).toList();
  }

  static WallpaperTag _toTag(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw UnexpectedResponseFailure(
        'expected a tag object, got ${raw.runtimeType}',
      );
    }
    return WallpaperTag(
      id: _readInt(raw, 'id', fallback: -1),
      name: _readString(raw, 'name'),
    );
  }

  static WallpaperUploader _readUploader(Map<String, dynamic> raw) {
    final Object? uploader = raw['uploader'];
    if (uploader is! Map<String, dynamic>) {
      throw const UnexpectedResponseFailure(
        'wallpaper is missing its "uploader" object',
      );
    }
    return WallpaperUploader(
      username: _readString(uploader, 'username'),
      group: _readOptionalString(uploader, 'group'),
      avatarUrl: _readOptionalString(uploader, 'avatar'),
    );
  }

  static String _readString(Map<String, dynamic> raw, String key) {
    final Object? value = raw[key];
    if (value is String && value.isNotEmpty) return value;
    throw UnexpectedResponseFailure(
      '"$key" must be a non-empty string, got "${value ?? 'null'}"',
    );
  }

  static String _readOptionalString(Map<String, dynamic> raw, String key) {
    final Object? value = raw[key];
    return value is String ? value : '';
  }

  static int _readInt(
    Map<String, dynamic> raw,
    String key, {
    required int fallback,
  }) {
    final Object? value = raw[key];
    if (value is int) return value;
    // Wallhaven sends meta numbers as strings on some endpoints.
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }
}
