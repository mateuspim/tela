import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/theme.dart';
import 'package:tela/core/ui/immersive_chrome_palette.dart';
import 'package:tela/core/ui/photo_capsule.dart';

Future<void> _pump(WidgetTester tester, ThemeData theme) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: PhotoCapsule(
            child: IconButton(
              icon: const Icon(Icons.fullscreen),
              onPressed: () {},
            ),
          ),
        ),
      ),
    ),
  );
}

ShapeDecoration _decoration(WidgetTester tester) {
  final DecoratedBox box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(PhotoCapsule),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return box.decoration as ShapeDecoration;
}

void main() {
  group('PhotoCapsule', () {
    testWidgets('fills with the viewer scrim, so the photo shows through', (
      WidgetTester tester,
    ) async {
      final ThemeData theme = TelaTheme.dark(null);
      await _pump(tester, theme);

      final Color fill = _decoration(tester).color!;
      expect(fill, ImmersiveChromePalette.fromScheme(theme.colorScheme).scrim);
      expect(fill.a, lessThan(1));
      expect(_decoration(tester).shape, isA<StadiumBorder>());
    });

    testWidgets('draws its controls white even in the light theme', (
      WidgetTester tester,
    ) async {
      // The light scheme's onSurface is near-black, which would vanish into a
      // near-black scrim.
      await _pump(tester, TelaTheme.light(null));

      final IconTheme icon = tester.widget<IconTheme>(
        find
            .ancestor(
              of: find.byIcon(Icons.fullscreen),
              matching: find.byType(IconTheme),
            )
            .first,
      );
      expect(icon.data.color, PhotoCapsule.ink);
    });
  });
}
