import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/models/wallpaper.dart';
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
    return WallpaperPage(
      wallpapers: data.map(_toWallpaper).toList(),
      currentPage: _readInt(meta, 'current_page', fallback: 1),
      lastPage: _readInt(meta, 'last_page', fallback: 1),
      seed: meta['seed'] as String?,
    );
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

  static String _readString(Map<String, dynamic> raw, String key) {
    final Object? value = raw[key];
    if (value is String && value.isNotEmpty) return value;
    throw UnexpectedResponseFailure(
      '"$key" must be a non-empty string, got "${value ?? 'null'}"',
    );
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
