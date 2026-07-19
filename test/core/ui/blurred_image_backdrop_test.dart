import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/network/wallpaper_image_caches.dart';
import 'package:tela/core/ui/blurred_image_backdrop.dart';
import 'package:tela/core/ui/gallery_viewport.dart';
import 'package:tela/core/ui/progressive_network_gallery_source.dart';

const String _backdropUrl = 'https://th.wallhaven.cc/orig/ab/abcdef.jpg';
const String _previewUrl = 'https://th.wallhaven.cc/orig/cd/cdefgh.jpg';
const String _imageUrl = 'https://w.wallhaven.cc/full/ab/wallhaven-abcdef.jpg';

void main() {
  group('BlurredImageBackdrop', () {
    testWidgets('reads the thumbnail cache, and decodes small', (
      WidgetTester tester,
    ) async {
      await _pumpBackdrop(tester);

      final CachedNetworkImage image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      // The shelf tile and the preview already fetched this exact URL into
      // this exact bucket, so the fill costs no request.
      expect(image.imageUrl, _backdropUrl);
      expect(image.cacheManager, same(thumbnailImageCache));
      // Blurred and stretched: a big decode would be memory spent on detail
      // the blur then destroys.
      expect(image.memCacheWidth, lessThanOrEqualTo(64));
      expect(image.fit, BoxFit.cover);
      // Scenery behind the real preview; a crossfade here reads as a flicker.
      expect(image.fadeInDuration, Duration.zero);
    });

    testWidgets('covers the whole box, which is the letterbox it fills', (
      WidgetTester tester,
    ) async {
      await _pumpBackdrop(tester, boxSize: const Size(400, 300));

      expect(
        tester.getSize(find.byType(BlurredImageBackdrop)),
        const Size(400, 300),
      );
      expect(
        tester.getSize(find.byType(CachedNetworkImage)),
        const Size(400, 300),
      );
    });

    testWidgets('stays silent when it cannot load', (
      WidgetTester tester,
    ) async {
      await _pumpBackdrop(tester);

      final CachedNetworkImage image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      final BuildContext context = tester.element(
        find.byType(BlurredImageBackdrop),
      );
      final Widget failure = image.errorWidget!(
        context,
        _backdropUrl,
        StateError('decode failed'),
      );

      // A failed backdrop is simply absent. An error glyph here would claim
      // the *preview* had failed, which it has not.
      expect(failure, isA<SizedBox>());
      await tester.pumpWidget(MaterialApp(home: failure));
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
    });

    testWidgets('takes no taps away from the image canvas', (
      WidgetTester tester,
    ) async {
      await _pumpBackdrop(tester);

      expect(
        tester
            .widget<IgnorePointer>(
              find.byKey(BlurredImageBackdrop.backdropKey),
            )
            .ignoring,
        isTrue,
      );
    });

    test('refuses a scrim that is not an opacity', () {
      expect(
        () => BlurredImageBackdrop(imageUrl: _backdropUrl, scrimOpacity: 1.5),
        throwsAssertionError,
      );
      expect(
        () => BlurredImageBackdrop(imageUrl: _backdropUrl, sigma: 0),
        throwsAssertionError,
      );
    });
  });

  group('GalleryViewport backdrop', () {
    testWidgets('fills the viewport, not the contained frame', (
      WidgetTester tester,
    ) async {
      await _pumpViewport(tester, withBackdrop: true);

      // The whole point of the slice: the dead band around a letterboxed
      // wallpaper is what gets painted, so the backdrop must be larger than
      // the fitted image it sits behind.
      final Size frame = tester.getSize(
        find.byKey(GalleryViewport.imageFrameKey),
      );
      final Size backdrop = tester.getSize(
        find.byKey(BlurredImageBackdrop.backdropKey),
      );
      expect(frame, const Size(300, 168.75));
      expect(backdrop, const Size(300, 600));
      expect(backdrop.height, greaterThan(frame.height));
    });

    testWidgets('sits under the zoom viewport, so a pinch cannot drag it', (
      WidgetTester tester,
    ) async {
      await _pumpViewport(tester, withBackdrop: true);

      // Inside InteractiveViewer the backdrop would zoom along with the image
      // and stop being a still background.
      expect(
        find.descendant(
          of: find.byType(InteractiveViewer),
          matching: find.byKey(BlurredImageBackdrop.backdropKey),
        ),
        findsNothing,
      );
      expect(find.byKey(BlurredImageBackdrop.backdropKey), findsOneWidget);
    });

    testWidgets('is absent by default, leaving the calm flat canvas', (
      WidgetTester tester,
    ) async {
      await _pumpViewport(tester);

      // The immersive viewer and the crop editor are judged on the frame's
      // real bounds; neither may grow scenery by accident.
      expect(find.byType(BlurredImageBackdrop), findsNothing);
      expect(find.byType(CachedNetworkImage), findsNWidgets(2));
    });
  });
}

Future<void> _pumpBackdrop(
  WidgetTester tester, {
  Size boxSize = const Size(300, 200),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: boxSize.width,
          height: boxSize.height,
          child: const BlurredImageBackdrop(imageUrl: _backdropUrl),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpViewport(
  WidgetTester tester, {
  bool withBackdrop = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(300, 600), devicePixelRatio: 2),
        child: Center(
          child: SizedBox(
            width: 300,
            height: 600,
            child: GalleryViewport(
              aspectRatio: 16 / 9,
              semanticsLabel: 'Chosen wallpaper',
              backdrop: withBackdrop
                  ? const BlurredImageBackdrop(imageUrl: _backdropUrl)
                  : null,
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
