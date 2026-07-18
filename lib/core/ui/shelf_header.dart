import 'package:flutter/material.dart';
import 'package:tela/app/theme.dart';

/// An editorial section header: a display-face kicker, an optional count in the
/// accent, and a hairline rule under both.
///
/// The plaque on tela's gallery wall. It is a shared widget so every shelf —
/// favorites today, the collections and history shelves that follow — reads as
/// one hand, and so the count is the app's one accent moment that is *text*
/// rather than a control. Pass [count] only where a number is worth stating;
/// most shelves are just a labelled rule.
///
/// ```dart
/// ShelfHeader(label: l10n.favoritesTitle, count: saved.length);
/// ```
class ShelfHeader extends StatelessWidget {
  /// Creates a shelf header labelled [label], optionally counting [count].
  const ShelfHeader({
    required this.label,
    this.count,
    this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 8),
    super.key,
  });

  /// The shelf's name. Shown upper-cased and tracked, plaque-style.
  final String label;

  /// How many items the shelf holds, or null to show no count.
  final int? count;

  /// Room around the header. The default matches the grid gutter beneath it.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Semantics(
        header: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(label.toUpperCase(), style: _kicker(scheme.onSurface)),
                if (count != null) ...<Widget>[
                  const SizedBox(width: 8),
                  Text('· $count', style: _kicker(scheme.primary)),
                ],
              ],
            ),
            const SizedBox(height: 11),
            Container(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: .7),
            ),
          ],
        ),
      ),
    );
  }

  /// The plaque lettering: display face, tracked wide, small — the register of
  /// an engraved wall label, not a heading that competes with the work.
  TextStyle _kicker(Color color) => TextStyle(
    fontFamily: TelaTheme.brandFontFamily,
    fontWeight: FontWeight.w700,
    fontSize: 13,
    letterSpacing: 1.3,
    color: color,
  );
}
