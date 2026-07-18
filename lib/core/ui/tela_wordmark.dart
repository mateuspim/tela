import 'package:flutter/material.dart';
import 'package:tela/app/theme.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';

/// tela's wordmark: the app's name set in the display face, tight and
/// lower-case.
///
/// The brand's one typographic signature, so it is a widget rather than a
/// scattered `Text` style — the rail shows it, and anywhere else that wants the
/// name gets the same lockup, not a near-miss. It reads the app title so the
/// name has a single source, and stays on [ColorScheme.onSurface] by default:
/// identity here is the letterforms, not a colour that would tie the brand to
/// whatever accent the user happens to have chosen.
///
/// ```dart
/// const TelaWordmark(fontSize: 22);
/// ```
class TelaWordmark extends StatelessWidget {
  /// Creates the wordmark at [fontSize], optionally in [color].
  const TelaWordmark({this.fontSize = 24, this.color, super.key});

  /// The cap height to set the name at.
  final double fontSize;

  /// Overrides the default [ColorScheme.onSurface] ink — for a coloured brand
  /// moment, or a wordmark sitting on an image.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Text(
      l10n.appTitle,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: TelaTheme.brandFontFamily,
        fontWeight: FontWeight.w700,
        fontSize: fontSize,
        // A grotesque this heavy needs to be pulled tight to read as a mark.
        letterSpacing: fontSize * -0.03,
        height: 1,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}
