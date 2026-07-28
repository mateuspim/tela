import 'package:tela/domain/ports/download_queue_anchor.dart';

/// In-memory [DownloadQueueAnchor] that records what the shade was told.
///
/// Keeps the whole history rather than the latest state, because the thing
/// worth asserting is usually how *often* it was spoken to: the queue
/// republishes after every settled entry, and a notice that re-posted on each
/// of them would flicker the shade through a batch of a hundred.
class FakeDownloadQueueAnchor implements DownloadQueueAnchor {
  /// Creates a fake that accepts holds, or refuses every one when [refuses] —
  /// Android's background-start restriction, which is not an error.
  FakeDownloadQueueAnchor({this.refuses = false});

  /// Whether the platform turns every hold down.
  final bool refuses;

  /// Every hold, in order, as `"title|body"`.
  final List<String> holds = <String>[];

  /// How many times the anchor was dropped.
  ///
  /// Counts **raw calls**, including repeats. Dropping a hold or a release
  /// whose words have not changed is the adapter's job, not the port's, so a
  /// fake that de-duplicated here would hide the very thing the adapter's own
  /// test exists to prove.
  int releases = 0;

  /// Whether an anchor is currently up.
  bool get held => holds.isNotEmpty && !refuses && !_released;
  bool _released = false;

  @override
  Future<bool> hold({required String title, required String body}) async {
    holds.add('$title|$body');
    _released = false;
    return !refuses;
  }

  @override
  Future<void> release() async {
    releases++;
    _released = true;
  }
}
