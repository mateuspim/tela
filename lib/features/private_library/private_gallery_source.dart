import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tela/core/ui/gallery_viewport.dart';
import 'package:tela/domain/models/local_preview.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/ports/local_preview_cache.dart';

/// Shows one app-private file, from disk and nowhere else.
///
/// Private files are plain `file:` locations under tela's internal dir, so the
/// shared [LocalPreviewCache] resolves them straight to their own path — a
/// non-temporary preview it must never release, because that path is the user's
/// own file, not tela's throwaway copy. There is deliberately no network
/// fallback: an explicit wallpaper's pixels never come back over the wire, so a
/// file that cannot be read renders a safe broken-image state instead.
class PrivateGallerySource implements GalleryImageSource {
  /// Creates a local-only source for one private [image].
  PrivateGallerySource({required this.image, required this.cache});

  /// The private file whose pixels are shown.
  final PrivateImage image;

  /// Resolves [PrivateImage.location] to a decodable path — here, itself.
  final LocalPreviewCache cache;

  @override
  Widget build(BuildContext context, GalleryImageRequest request) {
    return _PrivateFileImage(
      // Keyed by the location so moving to another image disposes this state
      // before the next one resolves.
      key: ValueKey<Uri>(image.location),
      image: image,
      cache: cache,
      request: request,
    );
  }
}

class _PrivateFileImage extends StatefulWidget {
  const _PrivateFileImage({
    required this.image,
    required this.cache,
    required this.request,
    super.key,
  });

  final PrivateImage image;
  final LocalPreviewCache cache;
  final GalleryImageRequest request;

  @override
  State<_PrivateFileImage> createState() => _PrivateFileImageState();
}

class _PrivateFileImageState extends State<_PrivateFileImage> {
  LocalPreview? _preview;
  bool _resolved = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    final LocalPreview? preview = await widget.cache.materialize(
      widget.image.location,
    );
    if (!mounted) {
      if (preview != null) unawaited(widget.cache.release(preview));
      return;
    }
    setState(() {
      _preview = preview;
      _resolved = true;
    });
  }

  @override
  void dispose() {
    final LocalPreview? preview = _preview;
    // A file: preview is non-temporary, so this is a no-op that never touches
    // the user's own file — release only reclaims tela's throwaway copies.
    if (preview != null) unawaited(widget.cache.release(preview));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LocalPreview? preview = _preview;
    if (!_resolved) return const SizedBox.expand();
    if (preview == null || _failed) return _broken();
    return Image.file(
      File(preview.path),
      fit: BoxFit.contain,
      cacheWidth: _cacheDimension(
        widget.request.logicalSize.width,
        widget.image.width,
      ),
      cacheHeight: _cacheDimension(
        widget.request.logicalSize.height,
        widget.image.height,
      ),
      gaplessPlayback: true,
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
        // A truncated file can pass materialisation and still fail to decode;
        // land on the same safe broken state a missing file would.
        scheduleMicrotask(() {
          if (mounted) setState(() => _failed = true);
        });
        return _broken();
      },
    );
  }

  /// The one thing shown for a corrupt or unreadable private file.
  Widget _broken() {
    return const Center(
      child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
    );
  }

  /// Caps the decode at the fitted size, clamped to the source when known.
  int? _cacheDimension(double logical, int? sourcePixels) {
    final int wanted = (logical * widget.request.devicePixelRatio).ceil();
    if (sourcePixels == null || sourcePixels <= 0) {
      return wanted > 0 ? wanted : null;
    }
    return wanted.clamp(1, sourcePixels);
  }
}
