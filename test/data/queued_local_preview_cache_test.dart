import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/storage/queued_local_preview_cache.dart';
import 'package:tela/domain/models/thumbnail_cancellation.dart';

import '../fakes/gated_local_preview_cache.dart';

Uri _tile(int n) => Uri.parse('file:///tile/$n');

void main() {
  late GatedLocalPreviewCache inner;
  late QueuedLocalPreviewCache queue;

  setUp(() {
    inner = GatedLocalPreviewCache();
    queue = QueuedLocalPreviewCache(inner, maxConcurrent: 2);
  });

  test('never runs more decodes than the cap', () async {
    for (var i = 0; i < 5; i++) {
      unawaited(queue.materializeThumbnail(_tile(i), 200));
    }
    await pumpEventQueue();

    expect(inner.inFlight, 2);
  });

  test('serves the newest waiting request first', () async {
    for (var i = 0; i < 4; i++) {
      unawaited(queue.materializeThumbnail(_tile(i), 200));
    }
    await pumpEventQueue();
    // 0 and 1 were started on arrival (queue was free); 2 and 3 now wait.
    inner.finish(_tile(0));
    await pumpEventQueue();

    expect(inner.started.last, _tile(3));
  });

  test('drops a request cancelled while it waited, without a decode', () async {
    final ThumbnailCancellation scrolledPast = ThumbnailCancellation();
    unawaited(queue.materializeThumbnail(_tile(0), 200));
    unawaited(queue.materializeThumbnail(_tile(1), 200));
    final Future<Object?> dropped = queue.materializeThumbnail(
      _tile(2),
      200,
      cancellation: scrolledPast,
    );
    scrolledPast.cancel();
    inner.finish(_tile(0));
    await pumpEventQueue();

    expect(await dropped, isNull);
    expect(inner.started, isNot(contains(_tile(2))));
  });

  test('starts the next request when one finishes', () async {
    for (var i = 0; i < 3; i++) {
      unawaited(queue.materializeThumbnail(_tile(i), 200));
    }
    await pumpEventQueue();
    expect(inner.started, hasLength(2));

    inner.finish(_tile(0));
    await pumpEventQueue();

    expect(inner.started, hasLength(3));
  });

  test('passes the inner answer through', () async {
    final Future<Object?> answer = queue.materializeThumbnail(_tile(0), 200);
    await pumpEventQueue();
    inner.finish(_tile(0));

    expect(await answer, isNotNull);
  });
}
