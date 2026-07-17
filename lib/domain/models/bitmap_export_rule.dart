import 'package:tela/domain/models/purity.dart';

/// Whether a wallpaper of [purity] may have its pixels leave the app.
///
/// The single rule behind every hand-off of real image bytes to somewhere tela
/// does not control — the share sheet's image option (`shareOptionsFor`) and
/// the system wallpaper editor (`AdjustWallpaper`). Both ask this rather than
/// testing purity themselves, so the two can never drift apart.
///
/// Explicit wallpapers live behind `FLAG_SECURE` and never leave app-private
/// storage under CLAUDE.md's NSFW rules, so handing their pixels to another app
/// is refused. That includes the OEM's own wallpaper picker: it is a separate
/// app holding its own wallpaper history, which is exactly the ungated index
/// the private tier exists to prevent.
///
/// A public *link* is not an export and never asks this — the Wallhaven page is
/// public at any purity, so it reveals nothing tela is holding back.
///
/// `sketchy` is not explicit here, matching `Wallpaper.isNsfw`,
/// `StorageSettings.choicesFor` and `shareOptionsFor`, which all draw the line
/// at [Purity.nsfw] alone.
///
/// ```dart
/// mayExportBitmap(Purity.sfw);  // true
/// mayExportBitmap(Purity.nsfw); // false
/// ```
bool mayExportBitmap(Purity purity) => purity != Purity.nsfw;
