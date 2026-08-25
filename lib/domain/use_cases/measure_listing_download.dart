import 'package:tela/domain/models/listing_download_size.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/use_cases/search_wallpapers.dart';

/// Asks a listing how big it is, for the confirmation before downloading it
/// whole.
///
/// **One request, deliberately.** The count comes from the first page's own
/// metadata, so measuring a 12,000-wallpaper tag costs exactly as much as
/// measuring a 12-wallpaper one. Anything that walked the listing to count it
/// would spend the user's rate limit answering a question they may well say no
/// to.
///
/// Goes through [SearchWallpapers] rather than the source, so the measurement
/// is taken under the same blocklist and the same NSFW-key guard the download
/// itself will run under — a count that ignored the blocklist would promise
/// more wallpapers than the walk could ever deliver.
///
/// ```dart
/// final ListingDownloadSize size = await MeasureListingDownload(
///   search: search,
/// )(query);
/// ```
class MeasureListingDownload {
  /// Creates the use case.
  const MeasureListingDownload({required SearchWallpapers search})
    : _search = search;

  final SearchWallpapers _search;

  /// Measures [query]'s whole listing.
  Future<ListingDownloadSize> call(SearchQuery query) async {
    final WallpaperPage first = await _search(query.atPage(1));
    final int? total = first.total;
    if (total == null) return const ListingDownloadSize.uncounted();
    return ListingDownloadSize(
      wallpapers: total,
      bytes: _extrapolate(first.wallpapers, total),
    );
  }

  /// The first page's mean file size, over the whole listing.
  ///
  /// Null on an empty page rather than zero: "roughly 0 bytes" is a claim, and
  /// an empty first page means there was nothing to measure.
  int? _extrapolate(List<Wallpaper> sample, int total) {
    if (sample.isEmpty) return null;
    final int sum = sample.fold(
      0,
      (int bytes, Wallpaper w) => bytes + w.fileSizeBytes,
    );
    return (sum / sample.length * total).round();
  }
}
