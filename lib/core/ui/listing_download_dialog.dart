import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/byte_size_text.dart';
import 'package:tela/domain/models/listing_download_size.dart';

/// Asks before committing to every wallpaper in a listing.
///
/// **The confirmation is the feature's safety, not its politeness.** "Download
/// all from @dude" and "download all from #anime" are one gesture over a
/// hundredfold difference in commitment — a few hundred megabytes against tens
/// of gigabytes — and nothing else on the screen tells them apart. So the count
/// goes in front of the user before anything is queued, and the button says
/// nothing until it can be read beside a number.
///
/// Answers true when the user committed. A source that publishes no count
/// still gets a dialog: it says so plainly rather than inventing a figure, and
/// the user decides on the listing's name alone.
///
/// ```dart
/// final bool go = await confirmListingDownload(
///   context,
///   listing: '#anime',
///   size: size,
/// );
/// ```
Future<bool> confirmListingDownload(
  BuildContext context, {
  required String listing,
  required ListingDownloadSize size,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(l10n.listingDownloadAllTitle(listing)),
      content: Text(_body(l10n, size)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.actionCancel),
        ),
        // An empty listing has nothing to commit to, so the dialog becomes a
        // statement with no second button rather than offering a download that
        // would queue nothing.
        if (!size.isEmpty)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.listingDownloadAllConfirm),
          ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// What the listing costs, in the most honest form the source allows.
String _body(AppLocalizations l10n, ListingDownloadSize size) {
  if (size.isEmpty) return l10n.listingDownloadAllEmpty;
  final int? wallpapers = size.wallpapers;
  if (wallpapers == null) return l10n.listingDownloadAllUncounted;
  final int? bytes = size.bytes;
  // "Roughly" carries the whole caveat: the size is the first page's mean over
  // the listing's count, and saying it exactly would be a fabrication.
  if (bytes == null) return l10n.listingDownloadAllCountedOnly(wallpapers);
  return l10n.listingDownloadAllCounted(wallpapers, formatBytes(bytes));
}
