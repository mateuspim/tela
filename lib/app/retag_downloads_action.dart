import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/download_tag_field.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/use_cases/retag_stored_images.dart';

/// Asks which tag to refile a selection of downloads under, then does it.
///
/// Lives at the composition root beside `moveToPrivate` and for the same
/// reason: the download history and the private library both offer it, and a
/// feature may not import another feature.
///
/// Answers false when the user backed out of the naming dialog — nothing moved
/// and the selection stays, exactly as a dismissed destination chooser leaves a
/// batch alone.
Future<bool> retagDownloads({
  required BuildContext context,
  required WidgetRef ref,
  required List<DownloadRecord> records,
}) async {
  if (records.isEmpty) return false;
  // Read before the async gap, like every other action here: a viewer can pop
  // itself, and the messenger has to outlive the context that offered it.
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final AppLocalizations l10n = AppLocalizations.of(context);
  final TagFolder? chosen = await askForTagFolder(context);
  if (chosen == null) return false;
  return _retagAndReport(
    ref,
    messenger,
    l10n,
    retags: <StoredImageRetag>[
      for (final DownloadRecord record in records)
        StoredImageRetag(
          ref: record.wallpaper.ref,
          purity: record.wallpaper.purity,
          tier: record.tier,
          location: record.location,
          to: chosen,
        ),
    ],
  );
}

/// The private library's twin, over images rather than history rows.
///
/// Declares [Purity.nsfw] for every image, the same asymmetry
/// `confirmAndMoveOutOfPrivate` documents: this tier keeps no record of what it
/// holds beyond a file name, so tela cannot prove an image is safe. It costs
/// nothing here — a retag never leaves the tier, so no destination is being
/// gated — and it means the fallback's copy still cannot land in Photos.
Future<bool> retagPrivateImages({
  required BuildContext context,
  required WidgetRef ref,
  required List<PrivateImage> images,
}) async {
  if (images.isEmpty) return false;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final AppLocalizations l10n = AppLocalizations.of(context);
  final TagFolder? chosen = await askForTagFolder(context);
  if (chosen == null) return false;
  return _retagAndReport(
    ref,
    messenger,
    l10n,
    retags: <StoredImageRetag>[
      for (final PrivateImage image in images)
        StoredImageRetag(
          ref: image.ref,
          purity: Purity.nsfw,
          // The image's own home, not a constant: the library lists two tiers
          // and a retag moves a file within whichever one holds it.
          tier: image.tier,
          location: image.location,
          to: chosen,
        ),
    ],
  );
}

/// Performs the retag and says how many really moved.
///
/// The tally is the honest subset rather than the count asked for — a file this
/// install no longer owns falls back to copy-and-delete, and that delete can be
/// declined at the system prompt. Reporting the request instead of the result
/// is how a user ends up believing a folder holds something it does not.
Future<bool> _retagAndReport(
  WidgetRef ref,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n, {
  required List<StoredImageRetag> retags,
}) async {
  final Set<WallpaperRef> moved = await ref.read(retagStoredImagesProvider)(
    retags,
  );
  // The WidgetRef variant. `refreshDownloadsFrom` takes a provider `Ref`, and
  // the two have no common supertype — casting between them compiles and then
  // throws.
  refreshDownloads(ref);
  final String message = moved.length == retags.length
      ? l10n.retagDone(moved.length)
      : l10n.retagPartial(moved.length, retags.length);
  showTelaToast(
    messenger,
    message,
    kind: moved.isEmpty ? ToastKind.failure : ToastKind.success,
  );
  return moved.isNotEmpty;
}
