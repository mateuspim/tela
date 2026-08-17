import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/immersive_chrome_palette.dart';

void main() {
  test('the scrim keeps the opacity of the Colors.black45 it replaced', () {
    final ImmersiveChromePalette chrome = ImmersiveChromePalette.fromScheme(
      _schemeSeededWith(const Color(0xFF3366CC)),
    );

    expect(chrome.scrim.a, closeTo(Colors.black45.a, 0.001));
  });

  test('two wallpapers give two scrims, so the tint travels', () {
    final ImmersiveChromePalette warm = ImmersiveChromePalette.fromScheme(
      _schemeSeededWith(const Color(0xFFCC5500)),
    );
    final ImmersiveChromePalette cool = ImmersiveChromePalette.fromScheme(
      _schemeSeededWith(const Color(0xFF0055CC)),
    );

    expect(warm.scrim, isNot(cool.scrim));
    expect(warm.scrim, isNot(Colors.black45));
  });

  /// The guard the whole blend exists for. L2b measured the phone bar's white
  /// controls at 2.9–3.1:1 against a genuinely pale wallpaper — the 3:1 floor
  /// for UI graphics and nothing more — so a scrim that took a light
  /// wallpaper's colour *directly* would spend the only margin there is.
  test('a pale wallpaper still gets a near-black scrim', () {
    final ColorScheme pale = _schemeSeededWith(const Color(0xFFFFF4E0));
    final ImmersiveChromePalette chrome = ImmersiveChromePalette.fromScheme(
      pale,
    );

    final Color opaque = Color.alphaBlend(chrome.scrim, Colors.white);
    expect(opaque.computeLuminance(), lessThan(0.5));
    expect(
      chrome.scrim.withValues(alpha: 1).computeLuminance(),
      lessThan(0.1),
    );
  });

  test('the ink is the scheme own, not a hardcoded white', () {
    final ColorScheme scheme = _schemeSeededWith(const Color(0xFF2E7D32));
    final ImmersiveChromePalette chrome = ImmersiveChromePalette.fromScheme(
      scheme,
    );

    expect(chrome.ink, scheme.onSurface);
    expect(chrome.disabledInk.a, closeTo(Colors.white38.a, 0.001));
  });
}

ColorScheme _schemeSeededWith(Color seed) {
  return ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
}
