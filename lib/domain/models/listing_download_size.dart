import 'package:meta/meta.dart';

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
/// final ListingDownloadSize size = await measureListingDownload(query);
/// size.isCounted ? '${size.wallpapers} wallpapers' : 'all wallpapers';
/// ```
@immutable
class ListingDownloadSize {
  /// Creates a measurement. [wallpapers] null means the source does not count.
  const ListingDownloadSize({required this.wallpapers, required this.bytes});

  /// A listing whose size the source refuses to state — Konachan's every
  /// listing, which publishes no metadata at all.
  const ListingDownloadSize.uncounted() : wallpapers = null, bytes = null;

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
}
