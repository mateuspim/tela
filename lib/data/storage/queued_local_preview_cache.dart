import 'dart:async';
import 'dart:collection';

import 'package:tela/domain/models/local_preview.dart';
import 'package:tela/domain/models/thumbnail_cancellation.dart';
import 'package:tela/domain/models/vault_thumbnail.dart';
import 'package:tela/domain/ports/local_preview_cache.dart';

/// A [LocalPreviewCache] that meters thumbnail requests before they reach the
/// native side.
///
/// A private library opening on hundreds of uncached images used to fire every
/// decode at once and in scroll order, so the tiles on screen waited behind the
/// ones already scrolled past. This decorator caps in-flight thumbnails at
/// [maxConcurrent], starts the **newest** request first (LIFO — the tile the
/// user is looking at was asked for last), and answers null, without calling
/// through, for any request whose [ThumbnailCancellation] was raised while it
/// waited. Every other method passes straight through.
///
/// ```dart
/// QueuedLocalPreviewCache(MethodChannelLocalPreviewCache(), maxConcurrent: 3);
/// ```
class QueuedLocalPreviewCache implements LocalPreviewCache {
  /// Wraps [_inner], allowing [maxConcurrent] thumbnails in flight at once.
  QueuedLocalPreviewCache(this._inner, {this.maxConcurrent = 3})
    : assert(
        maxConcurrent > 0,
        'maxConcurrent must be > 0, got $maxConcurrent',
      );

  final LocalPreviewCache _inner;

  /// The most thumbnail decodes allowed to run at the same time.
  final int maxConcurrent;

  final ListQueue<_PendingThumbnail> _waiting = ListQueue<_PendingThumbnail>();
  int _running = 0;

  @override
  Future<VaultThumbnail?> materializeThumbnail(
    Uri location,
    int maxDimensionPx, {
    ThumbnailCancellation? cancellation,
  }) {
    final _PendingThumbnail pending = _PendingThumbnail(
      location,
      maxDimensionPx,
      cancellation,
    );
    _waiting.addLast(pending);
    _pump();
    return pending.completer.future;
  }

  void _pump() {
    while (_running < maxConcurrent && _waiting.isNotEmpty) {
      final _PendingThumbnail next = _waiting.removeLast();
      if (next.cancellation?.isCancelled ?? false) {
        next.completer.complete(null);
        continue;
      }
      _running++;
      unawaited(_run(next));
    }
  }

  Future<void> _run(_PendingThumbnail pending) async {
    try {
      pending.completer.complete(
        await _inner.materializeThumbnail(
          pending.location,
          pending.maxDimensionPx,
        ),
      );
    } on Object catch (error, stack) {
      pending.completer.completeError(error, stack);
    } finally {
      _running--;
      _pump();
    }
  }

  @override
  Future<LocalPreview?> materialize(Uri location) =>
      _inner.materialize(location);

  @override
  Future<LocalPreview?> materializeRemote(Uri imageUrl) =>
      _inner.materializeRemote(imageUrl);

  @override
  Future<void> release(LocalPreview preview) => _inner.release(preview);
}

class _PendingThumbnail {
  _PendingThumbnail(this.location, this.maxDimensionPx, this.cancellation);

  final Uri location;
  final int maxDimensionPx;
  final ThumbnailCancellation? cancellation;
  final Completer<VaultThumbnail?> completer = Completer<VaultThumbnail?>();
}
