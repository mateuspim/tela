import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tela/core/ui/gallery_viewport.dart';

/// A network source that keeps an honest thumbnail visible while full pixels
/// load.
///
/// [previewUrl] must describe the same uncropped composition as [imageUrl].
/// Both layers are constrained to the one frame supplied by [GalleryViewport].
class ProgressiveNetworkGallerySource implements GalleryImageSource {
  /// Creates a progressive network source.
  ProgressiveNetworkGallerySource({
    required this.previewUrl,
    required this.imageUrl,
    required this.sourcePixelSize,
    this.fadeDuration = const Duration(milliseconds: 180),
  })  : assert(sourcePixelSize.width > 0, 'source width must be positive'),
        assert(sourcePixelSize.height > 0, 'source height must be positive');

  /// An aspect-ratio-preserving preview of [imageUrl].
  final String previewUrl;

  /// The final full-resolution image URL.
  final String imageUrl;

  /// The full source dimensions used to cap image decodes.
  final Size sourcePixelSize;

  /// The full-image fade duration when reduced motion is not requested.
  final Duration fadeDuration;

  @override
  Widget build(BuildContext context, GalleryImageRequest request) {
    final int cacheWidth = _cacheDimension(
      request.logicalSize.width,
      request.devicePixelRatio,
      sourcePixelSize.width,
    );
    final int cacheHeight = _cacheDimension(
      request.logicalSize.height,
      request.devicePixelRatio,
      sourcePixelSize.height,
    );
    final Duration effectiveFade =
        MediaQuery.disableAnimationsOf(context) ? Duration.zero : fadeDuration;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _image(
          previewUrl,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          fadeInDuration: Duration.zero,
          errorWidget: const Center(child: Icon(Icons.broken_image_outlined)),
        ),
        _image(
          imageUrl,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          fadeInDuration: effectiveFade,
          errorWidget: const SizedBox.expand(),
        ),
      ],
    );
  }

  Widget _image(
    String imageUrl, {
    required int cacheWidth,
    required int cacheHeight,
    required Duration fadeInDuration,
    required Widget errorWidget,
  }) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.contain,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      fadeInDuration: fadeInDuration,
      placeholder: (BuildContext context, String url) =>
          const SizedBox.expand(),
      errorWidget: (BuildContext context, String url, Object error) =>
          errorWidget,
    );
  }

  int _cacheDimension(double logical, double density, double sourcePixels) {
    return (logical * density).ceil().clamp(1, sourcePixels.round());
  }
}
