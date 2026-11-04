/// A flag a grid tile raises when it leaves the screen before its thumbnail
/// has even started decoding.
///
/// Pure Dart so the `LocalPreviewCache` port can carry it: a queue honouring it
/// drops the request instead of spending a native decode on a tile nobody sees
/// (a fling past hundreds of tiles otherwise queues them all ahead of the
/// visible ones).
///
/// ```dart
/// final token = ThumbnailCancellation();
/// cache.materializeThumbnail(uri, 400, cancellation: token);
/// token.cancel(); // from the tile's dispose()
/// ```
class ThumbnailCancellation {
  bool _cancelled = false;

  /// Whether the requester no longer wants the answer.
  bool get isCancelled => _cancelled;

  /// Marks the request abandoned. Idempotent.
  void cancel() => _cancelled = true;
}
