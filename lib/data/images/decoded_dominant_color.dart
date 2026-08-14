import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:tela/core/network/wallpaper_image_caches.dart';
import 'package:tela/domain/models/dominant_swatch.dart';
import 'package:tela/domain/models/wallpaper_color.dart';
import 'package:tela/domain/ports/dominant_color.dart';

/// [DominantColor] by decoding the thumbnail the shelf already fetched.
///
/// Costs no request in the ordinary case: the tile that led to this screen
/// pulled `thumbOriginalUrl` into [thumbnailImageCache], so this reads a file
/// that is already on disk. It decodes it again rather than reaching into
/// Flutter's image cache, because a decoded `ui.Image` there is sized for the
/// screen and this wants a deliberately tiny one.
///
/// ```dart
/// const DecodedDominantColor().of(wallpaper.thumbOriginalUrl);
/// ```
class DecodedDominantColor implements DominantColor {
  /// Creates the adapter over [cache], the thumbnail bucket by default.
  DecodedDominantColor({BaseCacheManager? cache})
    : _cache = cache ?? thumbnailImageCache;

  final BaseCacheManager _cache;

  /// Width the image is decoded to before its pixels are counted.
  ///
  /// Tiny on purpose. The answer is one colour, and a 32px decode already holds
  /// a thousand pixels to vote with — a full-size decode would spend megabytes
  /// and several frames of jank to move that answer by a shade nobody can see.
  static const int _sampleWidth = 32;

  @override
  Future<WallpaperColor?> of(String imageUrl) async {
    final Uint8List? bytes = await _bytesOf(imageUrl);
    if (bytes == null) return null;
    final List<int>? pixels = await _pixelsOf(bytes);
    if (pixels == null) return null;
    return dominantSwatch(pixels);
  }

  /// The cached file's bytes, or null when there is nothing to read.
  ///
  /// A tint is decoration: a failure here costs the tint and must never cost
  /// the screen, so every way this can go wrong ends in null rather than a
  /// throw — a cache miss, an unreadable file, a network the caller never
  /// asked to use.
  Future<Uint8List?> _bytesOf(String imageUrl) async {
    try {
      final FileInfo? cached = await _cache.getFileFromCache(imageUrl);
      if (cached == null) return null;
      return await cached.file.readAsBytes();
    } on Object {
      return null;
    }
  }

  /// Decodes [bytes] small and flattens them to 24-bit RGB.
  ///
  /// Transparent pixels are dropped rather than composited: a PNG's fully
  /// transparent margin would otherwise vote as whatever colour happens to sit
  /// in its unused channels.
  Future<List<int>?> _pixelsOf(Uint8List bytes) async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: _sampleWidth,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ByteData? data = await frame.image.toByteData();
      frame.image.dispose();
      codec.dispose();
      if (data == null) return null;
      return _rgbFrom(data);
    } on Object {
      return null;
    }
  }

  List<int> _rgbFrom(ByteData data) {
    final List<int> pixels = <int>[];
    for (int offset = 0; offset + 3 < data.lengthInBytes; offset += 4) {
      if (data.getUint8(offset + 3) < 0xFF) continue;
      pixels.add(
        (data.getUint8(offset) << 16) |
            (data.getUint8(offset + 1) << 8) |
            data.getUint8(offset + 2),
      );
    }
    return pixels;
  }
}
