import 'package:meta/meta.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

/// A wallpaper as the app knows it — the domain shape, never the API's.
///
/// Wallhaven's `/search` and `/w/{id}` return the same core fields, so one
/// model covers the grid and the detail screen; the detail-only extras (tags,
/// uploader, source) arrive as a separate model rather than as nullable fields
/// smeared across every grid item.
///
/// ```dart
/// final Wallpaper w = wallpapers.first;
/// Image.network(w.thumbSmallUrl); // grid
/// Image.network(w.fullImageUrl);  // preview / apply
/// ```
@immutable
class Wallpaper {
  /// Creates a wallpaper. All fields are required: a wallpaper with no
  /// [fullImageUrl] cannot be applied, which is the whole point of the app.
  const Wallpaper({
    required this.id,
    required this.source,
    required this.pageUrl,
    required this.fullImageUrl,
    required this.thumbSmallUrl,
    required this.thumbLargeUrl,
    required this.thumbOriginalUrl,
    required this.resolution,
    required this.fileSizeBytes,
    required this.purity,
    required this.category,
    required this.colors,
  });

  /// The id the source issued, e.g. `"e7jvjd"`. Unique within [source] only —
  /// anything that *stores* or *ticks* a wallpaper keys on [ref].
  final String id;

  /// Which site it came from. Two sources can issue the same [id].
  final SourceId source;

  /// The wallpaper's public page on the site it came from, e.g.
  /// `https://wallhaven.cc/w/e7jvjd`.
  ///
  /// Supplied by the mapper, not composed here: only the adapter knows its
  /// site's URL shape, and Konachan's even depends on the wallpaper's rating
  /// (a safe post links to `.net`, so sharing one never sends anyone to the
  /// NSFW-capable host).
  ///
  /// Public whatever the purity: it is the same page anyone reaches on the
  /// site, so linking to it exports nothing tela is holding back (see
  /// `ShareWallpaper.link`).
  final Uri pageUrl;

  /// Full-resolution image — what we download and what we set as the wallpaper.
  final String fullImageUrl;

  /// Small thumbnail — **cropped** by Wallhaven to a fixed 300x200, so it does
  /// *not* match [resolution]'s aspect ratio. Only safe inside a fixed-shape
  /// box; a ratio-preserving grid wants [thumbOriginalUrl].
  final String thumbSmallUrl;

  /// Preview-sized thumbnail, shown while [fullImageUrl] decodes. Also cropped.
  final String thumbLargeUrl;

  /// Thumbnail that keeps the image's true aspect ratio. The one the masonry
  /// grid must use — the cropped thumbs turn a wide landscape into a
  /// center-punched close-up when stretched to [resolution]'s ratio.
  final String thumbOriginalUrl;

  /// Pixel dimensions of [fullImageUrl].
  final Resolution resolution;

  /// Size of [fullImageUrl] in bytes.
  final int fileSizeBytes;

  /// How explicit the image is; drives storage routing and API-key gating.
  final Purity purity;

  /// Which bucket the source filed it under, or null where the source has no
  /// such axis at all — a booru has no general/anime/people distinction, and
  /// asserting one on its behalf would be tela inventing metadata.
  final Category? category;

  /// Dominant colours as hex strings (`"#660000"`), in Wallhaven's order.
  final List<String> colors;

  /// What identifies this wallpaper across sources — the storage key, the
  /// selection key, and the stem of its downloaded file name.
  WallpaperRef get ref => WallpaperRef(source, id);

  /// True when this image may not be shown or stored without the NSFW rules.
  ///
  /// Storage adapters branch on this, never on a UI flag — CLAUDE.md's hard
  /// invariant is that NSFW files are never MediaStore-indexed in any tier.
  bool get isNsfw => purity == Purity.nsfw;

  /// This wallpaper, routed as explicit — for a batch that holds explicit
  /// images and so lands together under the explicit rules (see
  /// `BatchRouting`). Never the other way: nothing here may make an explicit
  /// wallpaper read as safe.
  ///
  /// ```dart
  /// wallpaper.routedAsExplicit().isNsfw; // true
  /// ```
  Wallpaper routedAsExplicit() => Wallpaper(
    id: id,
    source: source,
    pageUrl: pageUrl,
    fullImageUrl: fullImageUrl,
    thumbSmallUrl: thumbSmallUrl,
    thumbLargeUrl: thumbLargeUrl,
    thumbOriginalUrl: thumbOriginalUrl,
    resolution: resolution,
    fileSizeBytes: fileSizeBytes,
    purity: Purity.nsfw,
    category: category,
    colors: colors,
  );

  @override
  bool operator ==(Object other) => other is Wallpaper && other.ref == ref;

  @override
  int get hashCode => ref.hashCode;

  @override
  String toString() => 'Wallpaper($ref, $resolution, ${purity.name})';
}
