import 'package:tela/data/konachan/konachan_query.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';

/// Maps Konachan's (Moebooru) JSON to domain models.
///
/// The only place that knows Konachan's field names — DTOs never escape `data/`
/// (CLAUDE.md), so there is no DTO class, just the mapping. Konachan sends a
/// **bare JSON array** of posts with no page metadata (PLAN §18.1), so the
/// page's identity and `hasMore` are supplied by the caller, not read from the
/// body. Every field is read defensively: a bad payload becomes an
/// [UnexpectedResponseFailure], not a crashed grid.
abstract final class KonachanMapper {
  /// Maps a `/post.json` array to a page of wallpapers.
  ///
  /// [currentPage] is the page requested (the body carries no page number) and
  /// `hasMore` follows from a full page: Konachan signals the end with a
  /// *short* page, so a page as long as it asked for probably has a successor.
  ///
  /// ```dart
  /// final WallpaperPage page = KonachanMapper.toPage(body, currentPage: 1);
  /// ```
  static WallpaperPage toPage(
    Object? body, {
    required int currentPage,
    int pageSize = konachanPageSize,
  }) {
    final List<dynamic> posts = _asPostList(body);
    return WallpaperPage(
      wallpapers: posts.map(_toWallpaper).toList(),
      currentPage: currentPage,
      // No page count to compare against — a full page means "ask for another".
      hasMore: posts.length >= pageSize,
    );
  }

  /// Maps the one-element array `tags=id:{n}` returns to full metadata.
  ///
  /// There is no per-post endpoint on Konachan (PLAN §18.1), so detail is a
  /// one-result search. An empty array is a real failure here, not an empty
  /// grid: either no post carries [id], or it was looked up on `.net` for a
  /// post that host will not serve (PLAN §18.4), which the adapter avoids by
  /// asking `.com`. Since ids can now be typed by hand, the first case is the
  /// ordinary one, so it raises [NotFoundFailure] and names the id.
  static WallpaperDetails toDetails(Object? body, {required String id}) {
    final List<dynamic> posts = _asPostList(body);
    if (posts.isEmpty) {
      throw NotFoundFailure(id);
    }
    final Map<String, dynamic> post = _asPost(posts.first);
    return WallpaperDetails(
      wallpaper: _toWallpaper(post),
      ratio: _ratioOf(post),
      fileType: _mimeOf(post),
      tags: _tagsOf(post),
      uploader: WallpaperUploader(
        username: _readOptionalString(post, 'author'),
        // Konachan has no uploader group or avatar — empty, not invented.
        group: '',
        avatarUrl: '',
      ),
      source: _readOptionalString(post, 'source'),
      // Konachan publishes no view count (PLAN §18.4); its `score` stands in
      // for a favorites figure.
      views: null,
      favorites: _readInt(post, 'score'),
    );
  }

  /// Every post's tags in a listing payload, keyed by id.
  ///
  /// The tags are **already here** — a booru's listing carries them and
  /// [toPage] simply drops them, because the domain `Wallpaper` has no place
  /// for a tag list and putting one there would mean new columns in three
  /// tables for data only the tag chooser wants. Reading them off the same
  /// response the grid was built from is what lets a Konachan selection be
  /// answered with no request at all.
  static Map<String, List<WallpaperTag>> tagsIn(Object? body) {
    return <String, List<WallpaperTag>>{
      for (final Object? raw in _asPostList(body))
        if (_asPost(raw) case final Map<String, dynamic> post)
          '${_readInt(post, 'id')}': _tagsOf(post),
    };
  }

  static Wallpaper _toWallpaper(Object? raw) {
    final Map<String, dynamic> post = _asPost(raw);
    final Purity purity = _purityOf(post);
    return Wallpaper(
      id: '${_readInt(post, 'id')}',
      source: SourceId.konachan,
      pageUrl: _pageUrl(post, purity),
      fullImageUrl: _readUrl(post, 'file_url'),
      // Konachan has no cropped thumbnail: every derivative keeps the aspect
      // ratio, so the small and original thumbs are the one ~150px preview.
      thumbSmallUrl: _readUrl(post, 'preview_url'),
      thumbOriginalUrl: _readUrl(post, 'preview_url'),
      thumbLargeUrl: _readUrl(post, 'sample_url'),
      resolution: Resolution(_readInt(post, 'width'), _readInt(post, 'height')),
      fileSizeBytes: _readInt(post, 'file_size'),
      purity: purity,
      // A booru has no general/anime/people axis — asserting one would be tela
      // inventing metadata (PLAN §17.3 item 4).
      category: null,
      colors: const <String>[],
    );
  }

  /// `rating` → [Purity], failing **closed**: an unrecognised rating becomes
  /// [Purity.nsfw] so a vocabulary tela does not know cannot leak past the NSFW
  /// rules (PLAN §17.4 / §18.4).
  static Purity _purityOf(Map<String, dynamic> post) {
    return switch (_readOptionalString(post, 'rating')) {
      's' => Purity.sfw,
      'q' => Purity.sketchy,
      _ => Purity.nsfw,
    };
  }

  /// The public post page, on the host that never over-shares: a safe post
  /// links to `.net`, so sharing one never sends anyone to the NSFW-capable
  /// domain (PLAN §18.2).
  static Uri _pageUrl(Map<String, dynamic> post, Purity purity) {
    final String host = purity == Purity.sfw
        ? KonachanHost.safe
        : KonachanHost.unrestricted;
    return Uri.parse('https://$host/post/show/${_readInt(post, 'id')}');
  }

  static String _ratioOf(Map<String, dynamic> post) {
    final int height = _readInt(post, 'height');
    if (height == 0) return '0';
    return (_readInt(post, 'width') / height).toStringAsFixed(2);
  }

  /// The MIME type, from `file_ext` where Konachan sends it, else the URL's
  /// extension. Unknown extensions fall back to a generic image type rather
  /// than throwing — the detail screen shows the label, it does not decode it.
  static String _mimeOf(Map<String, dynamic> post) {
    final String ext = _extOf(post).toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'image/$ext',
    };
  }

  static String _extOf(Map<String, dynamic> post) {
    final String declared = _readOptionalString(post, 'file_ext');
    if (declared.isNotEmpty) return declared;
    final String url = _readOptionalString(post, 'file_url');
    final int dot = url.lastIndexOf('.');
    return dot == -1 ? '' : url.substring(dot + 1);
  }

  /// The `tags` string split into names. Konachan tag names *are* the
  /// identifier, so no id is fetched — a per-tag `/tag.json` lookup buys nothing
  /// a `TagLink` can't do by name (PLAN §18.4).
  static List<WallpaperTag> _tagsOf(Map<String, dynamic> post) {
    return _readOptionalString(post, 'tags')
        .split(' ')
        .where((String name) => name.isNotEmpty)
        .map((String name) => WallpaperTag(name: name))
        .toList();
  }

  static List<dynamic> _asPostList(Object? body) {
    if (body is List) return body;
    throw UnexpectedResponseFailure(
      'expected a JSON array of posts, got ${body.runtimeType}',
    );
  }

  static Map<String, dynamic> _asPost(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    throw UnexpectedResponseFailure(
      'expected a post object, got ${raw.runtimeType}',
    );
  }

  /// Reads a URL field, refusing an empty one and normalising a
  /// protocol-relative `//host/...` some Moebooru mirrors emit.
  static String _readUrl(Map<String, dynamic> post, String key) {
    final String value = _readString(post, key);
    return value.startsWith('//') ? 'https:$value' : value;
  }

  static String _readString(Map<String, dynamic> post, String key) {
    final Object? value = post[key];
    if (value is String && value.isNotEmpty) return value;
    throw UnexpectedResponseFailure(
      '"$key" must be a non-empty string, got "${value ?? 'null'}"',
    );
  }

  static String _readOptionalString(Map<String, dynamic> post, String key) {
    final Object? value = post[key];
    return value is String ? value : '';
  }

  static int _readInt(Map<String, dynamic> post, String key) {
    final Object? value = post[key];
    if (value is int) return value;
    if (value is String) {
      final int? parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw UnexpectedResponseFailure(
      '"$key" must be an integer, got "${value ?? 'null'}"',
    );
  }
}
