import 'package:tela/domain/models/bitmap_export_rule.dart';
import 'package:tela/domain/models/purity.dart';

/// What a share action can send out about a wallpaper.
enum ShareOption {
  /// The public source page, as a link. Reveals nothing tela is holding.
  link,

  /// The full-resolution image file itself, exported off the device.
  image,

  /// The full-resolution image put on the system clipboard, for pasting
  /// straight into another app rather than picking it out of a chooser.
  clipboard,
}

/// The share options a wallpaper of [purity] may offer, in menu order.
///
/// Every wallpaper can share its public Wallhaven [ShareOption.link] — the page
/// exists on wallhaven.cc regardless of purity, so a link leaks nothing tela is
/// protecting.
///
/// Only non-explicit wallpapers may share the [ShareOption.image] **file**:
/// handing the bitmap to a receiving app that then keeps its own copy collides
/// with the NSFW rules in CLAUDE.md, so it is withheld exactly the way
/// `StorageSettings.choicesFor` withholds the gallery tier. That call belongs
/// to [mayExportBitmap] rather than to this function: the system wallpaper
/// editor hands the same bytes to the same kind of stranger — and keeps them in
/// its own wallpaper history — so the two must not drift apart.
///
/// **[ShareOption.clipboard] is offered at every purity, by the owner's
/// decision** (2026-08-13), having first shipped withheld. Copying is the app's
/// fastest way of getting a picture into another app, and refusing it for
/// explicit wallpapers made that route useless on exactly the images it was
/// most wanted for. Be clear about what it costs rather than dressing it up:
/// the clipboard is read by whichever app the user pastes into, so this is not
/// a *narrower* hand-off than the image file it sits beside — it is a wider one
/// that the user performs deliberately, at the moment of use, with nothing
/// retaining the bytes on tela's side. What it does not touch is the thing
/// CLAUDE.md's hard rules are actually about: nothing is MediaStore-indexed,
/// nothing leaves the app-private tier, and the private library has no copy
/// affordance at all. Explicit copies are additionally marked sensitive
/// (`ClipDescription.EXTRA_IS_SENSITIVE`), so Android 13's clipboard preview
/// shows a placeholder rather than the picture.
///
/// ```dart
/// shareOptionsFor(Purity.sfw);  // [link, image, clipboard]
/// shareOptionsFor(Purity.nsfw); // [link, clipboard]
/// ```
List<ShareOption> shareOptionsFor(Purity purity) {
  if (!mayExportBitmap(purity)) {
    return const <ShareOption>[ShareOption.link, ShareOption.clipboard];
  }
  return const <ShareOption>[
    ShareOption.link,
    ShareOption.image,
    ShareOption.clipboard,
  ];
}
