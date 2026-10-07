import 'package:flutter/material.dart';
import 'package:tela/core/ui/floating_capsule.dart';
import 'package:tela/core/ui/immersive_chrome_palette.dart';

/// The capsule for controls that sit **on a single photograph**: Detail's back
/// button and actions, its fullscreen button and page arrows.
///
/// The one place a capsule may be see-through. `FloatingCapsule` is opaque by
/// contract because frosted chrome over the browse wall was rejected in pass
/// A2 — sixty thumbnails showing through a search bar. Over one photo, the
/// photo *is* the subject, and the overhaul's binding decision keeps glass
/// exactly there (HANDOFF, floating-capsule overhaul, 2026-10-04). Nothing is
/// blurred: the fill is the viewer's own scrim ([ImmersiveChromePalette]),
/// near-black carrying the wallpaper's hue, so a pale sky cannot wash out the
/// white controls — the 3:1 lesson `DetailTopScrim.opacity` already paid for.
///
/// Same shape language as the rest of the chrome — stadium, hairline edge,
/// soft lift — so Detail reads as the same app as Browse. Ink is forced white,
/// as Detail's bar always was: the scheme's `onSurface` is dark in light mode
/// and would vanish into the scrim.
///
/// ```dart
/// PhotoCapsule(child: IconButton(icon: Icon(Icons.fullscreen), ...));
/// ```
class PhotoCapsule extends StatelessWidget {
  /// Creates a photo capsule around [child].
  const PhotoCapsule({
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// The controls, normally icon buttons.
  final Widget child;

  /// Space between the capsule's edge and [child].
  final EdgeInsetsGeometry padding;

  /// The controls' colour.
  static const Color ink = Colors.white;

  /// [ink] for a control that cannot be pressed.
  static const Color disabledInk = Colors.white38;

  @override
  Widget build(BuildContext context) {
    return CapsuleSurface(
      fill: ImmersiveChromePalette.of(context).scrim,
      // Light, not outlineVariant: the edge has to show against the photo,
      // not against a band, and a dark hairline on a dark scrim is nothing.
      edge: Colors.white.withValues(alpha: .16),
      shadows: const <BoxShadow>[
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
      padding: padding,
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: ink,
            disabledForegroundColor: disabledInk,
          ),
        ),
        child: IconTheme.merge(
          data: const IconThemeData(color: ink),
          child: child,
        ),
      ),
    );
  }
}
