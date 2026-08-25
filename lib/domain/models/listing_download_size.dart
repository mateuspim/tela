import 'package:meta/meta.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';

/// What downloading a whole listing would commit to, as far as the source will
/// say.
///
/// The number in front of the user before a bulk download starts. It exists
/// because "download everything tagged *anime*" and "download everything by
/// @dude" are the same gesture over wildly different commitments — hundreds of
/// gigabytes and a few hundred megabytes — and nothing else on the screen says
/// which one you are about to make.
///
/// ```dart
/// final ListingDownloadSize size = ListingDownloadSize.of(firstPage);
/// size.isCounted ? '${size.wallpapers} wallpapers' : 'all wallpapers';
/// ```
@immutable
class ListingDownloadSize {
  /// Creates a measurement. [wallpapers] null means the source does not count.
  const ListingDownloadSize({required this.wallpapers, required this.bytes});

  /// A listing whose size the source refuses to state — Konachan's every
  /// listing, which publishes no metadata at all.
  const ListingDownloadSize.uncounted() : wallpapers = null, bytes = null;

  /// Measures a listing from its first page alone.
  ///
  /// **One page, and that is the whole design.** The count is metadata the
  /// source already sent, so measuring a 12,000-wallpaper tag costs the same
  /// as measuring a 12-wallpaper one — nothing beyond the page the caller
  /// needed anyway. Walking a listing to count it would spend a 45-per-minute
  /// budget answering a question the user may well decline.
  factory ListingDownloadSize.of(WallpaperPage first) {
    final int? total = first.total;
    if (total == null) return const ListingDownloadSize.uncounted();
    return ListingDownloadSize(
      wallpapers: total,
      bytes: _extrapolate(first.wallpapers, total),
    );
  }

  /// How many wallpapers the listing holds, or null where the source does not
  /// count them.
  final int? wallpapers;

  /// Roughly how many bytes they occupy at full resolution, or null when there
  /// is nothing to extrapolate from.
  ///
  /// **An estimate, and never presented as anything else.** It is the mean file
  /// size of the first page multiplied by [wallpapers] — the only figure
  /// available without fetching every page, which is the very thing the user is
  /// deciding whether to do.
  final int? bytes;

  /// Whether the source stated a count. False means the confirmation has to ask
  /// for "all wallpapers" without being able to say how many.
  bool get isCounted => wallpapers != null;

  /// Whether there is anything at all to download.
  bool get isEmpty => wallpapers == 0;

  /// The sample's mean file size, over the whole listing.
  ///
  /// Null on an empty page rather than zero: "roughly 0 bytes" is a claim, and
  /// an empty first page means there was nothing to measure.
  static int? _extrapolate(List<Wallpaper> sample, int total) {
    if (sample.isEmpty) return null;
    final int sum = sample.fold(
      0,
      (int bytes, Wallpaper w) => bytes + w.fileSizeBytes,
    );
    return (sum / sample.length * total).round();
  }
}
