import 'dart:async';

import 'package:tela/domain/models/local_preview.dart';
import 'package:tela/domain/models/thumbnail_cancellation.dart';
import 'package:tela/domain/models/vault_thumbnail.dart';
import 'package:tela/domain/ports/local_preview_cache.dart';

/// A [LocalPreviewCache] whose thumbnails stay in flight until the test
/// finishes them, so a queue's ordering and cap can be observed.
class GatedLocalPreviewCache implements LocalPreviewCache {
  /// Locations whose native decode has started, in start order.
  final List<Uri> started = <Uri>[];

  final Map<Uri, Completer<VaultThumbnail?>> _gates =
      <Uri, Completer<VaultThumbnail?>>{};

  /// How many decodes are started and not yet [finish]ed.
  int get inFlight => _gates.values.where((c) => !c.isCompleted).length;

  /// Completes [location]'s decode with a thumbnail.
  void finish(Uri location) {
    _gates[location]!.complete(
      VaultThumbnail(path: '/thumb/${location.path}', width: 4, height: 3),
    );
  }

  @override
  Future<VaultThumbnail?> materializeThumbnail(
    Uri location,
    int maxDimensionPx, {
    ThumbnailCancellation? cancellation,
  }) {
    started.add(location);
    return (_gates[location] = Completer<VaultThumbnail?>()).future;
  }

  @override
  Future<LocalPreview?> materialize(Uri location) async =>
      LocalPreview(path: '/p/${location.path}', isTemporary: true);

  @override
  Future<LocalPreview?> materializeRemote(Uri imageUrl) async => null;

  @override
  Future<void> release(LocalPreview preview) async {}
}
