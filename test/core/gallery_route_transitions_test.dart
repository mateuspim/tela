import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/gallery_route_transitions.dart';

void main() {
  group('galleryTransitionDuration', () {
    testWidgets('is instant when the platform disables animations', (
      WidgetTester tester,
    ) async {
      final Duration duration = await _durationFor(
        tester,
        disableAnimations: true,
      );

      expect(duration, Duration.zero);
    });

    testWidgets('is a short, spatially coherent motion otherwise', (
      WidgetTester tester,
    ) async {
      final Duration duration = await _durationFor(
        tester,
        disableAnimations: false,
      );

      expect(duration, greaterThan(Duration.zero));
      expect(duration.inMilliseconds, lessThanOrEqualTo(300));
    });
  });
}

Future<Duration> _durationFor(
  WidgetTester tester, {
  required bool disableAnimations,
}) async {
  late Duration duration;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Builder(
        builder: (BuildContext context) {
          duration = galleryTransitionDuration(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return duration;
}
