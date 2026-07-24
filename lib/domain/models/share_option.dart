import 'package:tela/domain/models/bitmap_export_rule.dart';
import 'package:tela/domain/models/purity.dart';

/// What a share action can send out about a wallpaper.
enum ShareOption {
  /// The public source page, as a link. Reveals nothing tela is holding.
  link,

  /// The full-resolution image file itself, exported off the device.
  image,
}

/// The share options a wallpaper of [purity] may offer, in menu order.
///
/// Every wallpaper can share its public Wallhaven [ShareOption.link] — the page
/// exists on wallhaven.cc regardless of purity, so a link leaks nothing tela is
/// protecting. Only non-explicit wallpapers may share the [ShareOption.image]
/// file: sending the actual bitmap off the device collides with the NSFW rules
/// in CLAUDE.md (explicit files live behind `FLAG_SECURE` and never leave
/// app-private), so it is withheld exactly the way `StorageSettings.choicesFor`
/// withholds the gallery tier. That call belongs to [mayExportBitmap] rather
/// than to this function: the system wallpaper editor hands the same bytes to
/// the same kind of stranger, and the two must not be able to drift apart.
/// Enforced here in the domain, not only in the menu that reads it —
/// `ShareWallpaper.image` guards the same rule.
///
/// ```dart
/// shareOptionsFor(Purity.sfw);  // [link, image]
/// shareOptionsFor(Purity.nsfw); // [link]
/// ```
List<ShareOption> shareOptionsFor(Purity purity) {
  if (!mayExportBitmap(purity)) return const <ShareOption>[ShareOption.link];
  return const <ShareOption>[ShareOption.link, ShareOption.image];
}
