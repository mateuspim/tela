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
/// A public *link* is not an export and never asks this — the source page is
/// public at any purity, so it reveals nothing tela is holding back.
///
/// **The beam is the one deliberate exception, and it has its own rule rather
/// than a hole punched through this one** — see [mayBeamBitmap]. Do not relax
/// this function to cover it: the two destinations are different in kind, and
/// collapsing them would quietly re-open the share sheet and the OEM editor.
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

/// Whether a wallpaper of [purity] may be beamed to a machine on the LAN.
///
/// Deliberately *not* [mayExportBitmap], and the difference is the threat
/// model rather than a softening of the rule. [mayExportBitmap] refuses to
/// hand explicit pixels to **another app on this device**, because that app
/// keeps its own wallpaper history — the ungated index the private tier exists
/// to prevent, and the thing that put explicit thumbnails in an OEM picker.
/// A beam has no such index: it is one file, addressed to one machine the
/// owner already controls, over their own network, to a receiver that writes
/// it wherever they told it to.
///
/// **[explicitBeamEnabled] starts false and is only ever true because someone
/// turned it on in Settings.** That is the whole safeguard: the capability
/// exists, but never by default and never by muscle memory, so a mis-tap on a
/// private-library tile cannot put an explicit file on a desktop. Owner's
/// call, 2026-08-26.
///
/// Safe and sketchy content is beamable regardless, matching every other rule
/// here that draws the line at [Purity.nsfw] alone.
///
/// ```dart
/// mayBeamBitmap(Purity.nsfw, explicitBeamEnabled: false); // false
/// mayBeamBitmap(Purity.nsfw, explicitBeamEnabled: true);  // true
/// ```
bool mayBeamBitmap(Purity purity, {required bool explicitBeamEnabled}) =>
    purity != Purity.nsfw || explicitBeamEnabled;
