import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/gallery_viewport.dart';
import 'package:tela/core/ui/progressive_network_gallery_source.dart';

void main() {
  group('containedImageSize', () {
    final List<(String, Size, double, Size)> cases =
        <(String, Size, double, Size)>[
      (
        'landscape source on compact portrait',
        const Size(390, 844),
        16 / 9,
        const Size(390, 219.375),
      ),
      (
        'portrait source on compact landscape',
        const Size(844, 390),
        9 / 16,
        const Size(219.375, 390),
      ),
      (
        'square source on an expanded landscape surface',
        const Size(1200, 800),
        1,
        const Size(800, 800),
      ),
      (
        'extreme portrait source',
        const Size(390, 844),
        0.1,
        const Size(84.4, 844),
      ),
    ];

    for (final (String name, Size viewport, double ratio, Size expected)
        in cases) {
      test(name, () {
        final Size actual = containedImageSize(
          viewportSize: viewport,
          aspectRatio: ratio,
        );

        expect(actual.width, closeTo(expected.width, 0.001));
        expect(actual.height, closeTo(expected.height, 0.001));
      });
    }

    test('rejects a ratio that cannot describe an image', () {
      expect(
        () => containedImageSize(
          viewportSize: const Size(390, 844),
          aspectRatio: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  testWidgets('constrains both progressive layers to one contained frame', (
    WidgetTester tester,
  ) async {
    await _pumpViewport(tester);

    final Finder images = find.byType(CachedNetworkImage);
    expect(images, findsNWidgets(2));
    expect(tester.getSize(images.at(0)), const Size(300, 168.75));
    expect(tester.getSize(images.at(1)), const Size(300, 168.75));
    expect(
      tester.getSize(find.byKey(GalleryViewport.imageFrameKey)),
      const Size(300, 168.75),
    );
  });

  testWidgets('uses display-sized decode bounds and keeps the preview fallback',
      (
    WidgetTester tester,
  ) async {
    await _pumpViewport(tester);

    final List<CachedNetworkImage> images = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .toList();
    expect(
      images.map((CachedNetworkImage image) => image.imageUrl),
      <String>[_previewUrl, _imageUrl],
    );
    for (final CachedNetworkImage image in images) {
      expect(image.fit, BoxFit.contain);
      expect(image.memCacheWidth, 600);
      expect(image.memCacheHeight, 338);
    }
    expect(images.first.fadeInDuration, Duration.zero);
    expect(images.last.fadeInDuration, const Duration(milliseconds: 180));
  });

  testWidgets('removes the progressive fade when animations are disabled', (
    WidgetTester tester,
  ) async {
    await _pumpViewport(tester, disableAnimations: true);

    final List<CachedNetworkImage> images = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .toList();
    expect(images.first.fadeInDuration, Duration.zero);
    expect(images.last.fadeInDuration, Duration.zero);
  });

  testWidgets('recomputes the contained frame after an orientation change', (
    WidgetTester tester,
  ) async {
    await _pumpViewport(
      tester,
      aspectRatio: 9 / 16,
    );
    Size frame = tester.getSize(find.byKey(GalleryViewport.imageFrameKey));
    expect(frame.width, closeTo(300, 0.001));
    expect(frame.height, closeTo(533.333, 0.001));

    await _pumpViewport(
      tester,
      viewportSize: const Size(600, 300),
      aspectRatio: 9 / 16,
    );
    frame = tester.getSize(find.byKey(GalleryViewport.imageFrameKey));
    expect(frame.width, closeTo(168.75, 0.001));
    expect(frame.height, closeTo(300, 0.001));
  });

  testWidgets('keeps a thumbnail fallback and a safe broken-image state', (
    WidgetTester tester,
  ) async {
    await _pumpViewport(tester);

    final List<CachedNetworkImage> images = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .toList();
    final BuildContext context = tester.element(find.byType(GalleryViewport));
    final Widget previewFailure = images.first.errorWidget!(
      context,
      _previewUrl,
      StateError('decode failed'),
    );
    final Widget fullFailure = images.last.errorWidget!(
      context,
      _imageUrl,
      StateError('decode failed'),
    );

    // A failed full image is transparent, leaving the honest thumbnail below.
    expect(fullFailure, isA<SizedBox>());
    await tester.pumpWidget(MaterialApp(home: previewFailure));
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  testWidgets('exposes one meaningful image semantic', (
    WidgetTester tester,
  ) async {
    await _pumpViewport(tester);

    expect(find.bySemanticsLabel('Chosen wallpaper'), findsOneWidget);
  });
}

Future<void> _pumpViewport(
  WidgetTester tester, {
  bool disableAnimations = false,
  Size viewportSize = const Size(300, 600),
  double aspectRatio = 16 / 9,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: viewportSize,
          devicePixelRatio: 2,
          disableAnimations: disableAnimations,
        ),
        child: Center(
          child: SizedBox(
            width: viewportSize.width,
            height: viewportSize.height,
            child: GalleryViewport(
              aspectRatio: aspectRatio,
              semanticsLabel: 'Chosen wallpaper',
              source: ProgressiveNetworkGallerySource(
                previewUrl: _previewUrl,
                imageUrl: _imageUrl,
                sourcePixelSize: const Size(3840, 2160),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

const String _previewUrl = 'https://example.com/original-thumbnail.jpg';
const String _imageUrl = 'https://example.com/full-image.jpg';
