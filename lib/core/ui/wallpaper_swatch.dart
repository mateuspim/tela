import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/wallpaper_color.dart';

/// A round chip of one [WallpaperColor], selectable or not.
///
/// Shared by the detail screen's dominant-colour row and the filter sheet's
/// palette, because they are the same 29 Wallhaven colours drawn the same way —
/// and because the alpha-and-radix arithmetic that turns `#rrggbb` into a
/// [Color] should exist once.
///
/// ```dart
/// WallpaperSwatch(color: WallpaperColor('#0066cc'), onTap: _filterByIt);
/// ```
class WallpaperSwatch extends StatelessWidget {
  /// Creates a swatch. Without [onTap] it is a label, not a control.
  const WallpaperSwatch({
    required this.color,
    this.selected = false,
    this.onTap,
    super.key,
  });

  /// The colour to paint.
  final WallpaperColor color;

  /// Whether this is the colour the search is currently filtered by.
  final bool selected;

  /// Called when tapped. Null renders a plain, non-interactive chip.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: onTap != null,
      selected: onTap == null ? null : selected,
      label: l10n.colorSwatchLabel(color.hex),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: _diameter,
          height: _diameter,
          decoration: BoxDecoration(
            color: Color(_opaque | color.rgb),
            shape: BoxShape.circle,
            // Always outlined: #ffffff on a light surface is otherwise an
            // invisible swatch, and #000000 disappears the same way in dark.
            border: Border.all(
              color: selected ? scheme.primary : scheme.outline,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected ? _check() : null,
        ),
      ),
    );
  }

  /// A tick that stays legible on all 29 swatches, black and white included.
  Icon _check() {
    final Color painted = Color(_opaque | color.rgb);
    return Icon(
      Icons.check,
      size: 20,
      color: painted.computeLuminance() > 0.5 ? Colors.black : Colors.white,
    );
  }

  /// Wallhaven's palette is RGB; the alpha channel is ours to supply.
  static const int _opaque = 0xff000000;

  static const double _diameter = 40;
}
