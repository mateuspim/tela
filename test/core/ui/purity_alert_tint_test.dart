import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/purity_alert_tint.dart';
import 'package:tela/domain/models/purity.dart';

void main() {
  final ColorScheme colors = ColorScheme.fromSeed(
    seedColor: const Color(0xFF7772E5),
    brightness: Brightness.dark,
  );

  group('purityAlertTint', () {
    test('leaves a safe wallpaper untinted', () {
      expect(purityAlertTint(colors, Purity.sfw), isNull);
    });

    // Sketchy earns the tint precisely because it does *not* route to the
    // private library: it follows the safe setting into the gallery, and the
    // tint is the only thing that says so before the tap.
    test('tints sketchy as well as explicit', () {
      expect(purityAlertTint(colors, Purity.sketchy), colors.error);
      expect(purityAlertTint(colors, Purity.nsfw), colors.error);
    });
  });
}
