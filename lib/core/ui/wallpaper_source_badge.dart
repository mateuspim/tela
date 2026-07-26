import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';

/// A small pill naming the source a grid tile's wallpaper came from.
///
/// It lives in the tile's bottom-left corner — the one the selection tick
/// (top-left), the missing badge (top-right) and the "you already have this"
/// marks (bottom-right) all leave free, so the four never collide.
///
/// Only shelves that can hold more than one source draw it: on the browse wall
/// every tile is the active source, so a badge on all of them would say
/// nothing — the same reasoning that narrows a shelf's visible marks.
class WallpaperSourceBadge extends StatelessWidget {
  /// Creates a badge reading [sourceName], the source's display name.
  const WallpaperSourceBadge({required this.sourceName, super.key});

  /// The human name of the source, e.g. `'Wallhaven'` or `'Konachan'`.
  final String sourceName;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      label: AppLocalizations.of(context).wallpaperSourceBadge(sourceName),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // The same 0.82 the marks pill and the tick use, and for the same
          // reason: legible over a wallpaper of any luminance.
          color: colors.surface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          // The visible name is already in the Semantics label above; excluding
          // it here stops a screen reader hearing "Wallhaven, From Wallhaven".
          child: ExcludeSemantics(
            child: Text(
              sourceName,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
