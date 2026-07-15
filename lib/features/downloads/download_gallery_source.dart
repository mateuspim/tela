import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tela/core/ui/gallery_viewport.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/local_preview.dart';
import 'package:tela/domain/ports/local_preview_cache.dart';
import 'package:tela/features/detail/progressive_wallpaper_preview.dart';

/// Shows a download's saved file first, then Wallhaven if it cannot be read.
///
/// This is why History works offline: the pixels come from the copy the
/// download already left on the device, materialised through [cache] because a
/// MediaStore or SAF location is not a path `FileImage` can decode. If that
/// file is gone — deleted from Photos or a file manager behind tela's back —
/// the same network source the grid's badge warns about takes over.
class DownloadGallerySource implements GalleryImageSource {
  /// Creates a local-first source for one [record].
  DownloadGallerySource({required this.record, required this.cache});

  /// The download whose saved file is preferred over its Wallhaven URL.
  final DownloadRecord record;

  /// Materialises [DownloadRecord.location] into a decodable local file.
  final LocalPreviewCache cache;

  @override
  Widget build(BuildContext context, GalleryImageRequest request) {
    return _LocalFirstImage(
      // Keyed by the location so moving to another record disposes this state
      // and releases its throwaway preview before the next one materialises.
      key: ValueKey<Uri>(record.location),
      record: record,
      cache: cache,
      request: request,
    );
  }
}

class _LocalFirstImage extends StatefulWidget {
  const _LocalFirstImage({
    required this.record,
    required this.cache,
    required this.request,
    super.key,
  });

  final DownloadRecord record;
  final LocalPreviewCache cache;
  final GalleryImageRequest request;

  @override
  State<_LocalFirstImage> createState() => _LocalFirstImageState();
}

class _LocalFirstImageState extends State<_LocalFirstImage> {
  LocalPreview? _preview;
  bool _resolved = false;
  bool _localFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_materialise());
  }

  Future<void> _materialise() async {
    final LocalPreview? preview = await widget.cache.materialize(
      widget.record.location,
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
    if (preview != null) unawaited(widget.cache.release(preview));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LocalPreview? preview = _preview;
    if (!_resolved || preview == null || _localFailed) {
      // A brief black frame while materialising, then the network source once
      // it is clear no readable local file exists — never a flash of Wallhaven
      // over a file that is actually here.
      if (_resolved && (preview == null || _localFailed)) return _network();
      return const SizedBox.expand();
    }
    return Image.file(
      File(preview.path),
      fit: BoxFit.contain,
      cacheWidth: _cacheDimension(
        widget.request.logicalSize.width,
        widget.record.wallpaper.resolution.width,
      ),
      cacheHeight: _cacheDimension(
        widget.request.logicalSize.height,
        widget.record.wallpaper.resolution.height,
      ),
      gaplessPlayback: true,
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
        // A canRead probe can pass and a decode still fail on a truncated file;
        // fall through to the network the same way a missing file would.
        scheduleMicrotask(() {
          if (mounted) setState(() => _localFailed = true);
        });
        return const SizedBox.expand();
      },
    );
  }

  Widget _network() {
    return ProgressiveWallpaperPreview.sourceFor(
      widget.record.wallpaper,
    ).build(context, widget.request);
  }

  int _cacheDimension(double logical, int sourcePixels) {
    final double density = widget.request.devicePixelRatio;
    return (logical * density).ceil().clamp(1, sourcePixels);
  }
}
