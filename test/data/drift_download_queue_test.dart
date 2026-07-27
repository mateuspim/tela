import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/data/downloads/drift_download_queue.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/queued_download.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

void main() {
  late TelaDatabase db;
  late DriftDownloadQueue queue;

  setUp(() {
    db = TelaDatabase(NativeDatabase.memory());
    queue = DriftDownloadQueue(db);
  });

  tearDown(() => db.close());

  group('DriftDownloadQueue', () {
    test('keeps the line in the order it was queued', () async {
      await queue.enqueue(_entries(<String>['a', 'b', 'c']));

      final List<QueuedDownload> entries = await queue.entries();

      expect(
        entries.map((QueuedDownload e) => e.ref.id),
        <String>['a', 'b', 'c'],
      );
    });

    test('enqueuing the same wallpaper again changes nothing', () async {
      // Re-ticking a shelf must not line the same wallpaper up twice, and must
      // not reset an entry that has already been tried.
      await queue.enqueue(_entries(<String>['a']));
      await queue.claimNext();
      await queue.markFailed(_ref('a'), ImageStoreProblem.source);

      await queue.enqueue(_entries(<String>['a']));

      final QueuedDownload entry = (await queue.entries()).single;
      expect(entry.state, DownloadQueueState.failed);
      expect(entry.failure, ImageStoreProblem.source);
      expect(entry.attempts, 1);
    });

    test(
      'holds explicit and app-private entries, unlike the history',
      () async {
        // The queue is a work list, not an index: dropping these would silently
        // decline a download the user asked for. See DownloadQueue's docstring.
        await queue.enqueue(<QueuedDownload>[
          _entry('a', purity: Purity.nsfw, tier: StorageTier.appPrivate),
        ]);

        final QueuedDownload entry = (await queue.entries()).single;
        expect(entry.wallpaper.purity, Purity.nsfw);
        expect(entry.tier, StorageTier.appPrivate);
      },
    );

    test('claims the oldest pending entry and counts the attempt', () async {
      await queue.enqueue(_entries(<String>['a', 'b']));

      final QueuedDownload? claimed = await queue.claimNext();

      expect(claimed?.ref.id, 'a');
      expect(claimed?.state, DownloadQueueState.running);
      expect(claimed?.attempts, 1);
    });

    test('never claims the same entry twice', () async {
      await queue.enqueue(_entries(<String>['a']));

      expect((await queue.claimNext())?.ref.id, 'a');
      expect(await queue.claimNext(), isNull);
    });

    test('answers null on an empty queue rather than throwing', () async {
      expect(await queue.claimNext(), isNull);
    });

    test('a failure keeps its entry, its reason and its attempt', () async {
      await queue.enqueue(_entries(<String>['a']));
      await queue.claimNext();

      await queue.markFailed(_ref('a'), ImageStoreProblem.folderUnavailable);

      final QueuedDownload entry = (await queue.entries()).single;
      expect(entry.state, DownloadQueueState.failed);
      expect(entry.failure, ImageStoreProblem.folderUnavailable);
      expect(entry.attempts, 1);
    });

    test('a failed entry is not claimable until it is requeued', () async {
      await queue.enqueue(_entries(<String>['a']));
      await queue.claimNext();
      await queue.markFailed(_ref('a'), ImageStoreProblem.source);
      expect(await queue.claimNext(), isNull);

      await queue.requeue(_ref('a'));

      expect((await queue.claimNext())?.ref.id, 'a');
    });

    test('requeuing clears the reason but keeps the attempt count', () async {
      // A wallpaper that has failed three times should still look like it.
      await queue.enqueue(_entries(<String>['a']));
      await queue.claimNext();
      await queue.markFailed(_ref('a'), ImageStoreProblem.source);

      await queue.requeue(_ref('a'));

      final QueuedDownload entry = (await queue.entries()).single;
      expect(entry.failure, isNull);
      expect(entry.attempts, 1);
    });

    test('requeueFailed moves only the failed ones, and counts them', () async {
      await queue.enqueue(_entries(<String>['a', 'b', 'c']));
      await queue.claimNext();
      await queue.markFailed(_ref('a'), ImageStoreProblem.source);

      expect(await queue.requeueFailed(), 1);
      expect(
        (await queue.entries()).every(
          (QueuedDownload e) => e.state == DownloadQueueState.pending,
        ),
        isTrue,
      );
    });

    test('removing an entry that was never queued is not an error', () async {
      await queue.remove(_ref('nope'));

      expect(await queue.entries(), isEmpty);
    });

    test('clear empties the queue', () async {
      await queue.enqueue(_entries(<String>['a', 'b']));

      await queue.clear();

      expect(await queue.entries(), isEmpty);
    });

    test(
      'resumeInterrupted demotes what a killed process left running',
      () async {
        // `running` is only true inside the process that claimed it. A
        // row still wearing it on launch is claimed by nothing, and
        // claimNext only ever takes pending ones — so without this it is
        // stranded forever.
        await queue.enqueue(_entries(<String>['a']));
        await queue.claimNext();

        await queue.resumeInterrupted();

        expect(
          (await queue.entries()).single.state,
          DownloadQueueState.pending,
        );
        expect((await queue.claimNext())?.ref.id, 'a');
      },
    );

    test('resumeInterrupted leaves pending and failed entries alone', () async {
      await queue.enqueue(_entries(<String>['a', 'b']));
      await queue.claimNext();
      await queue.markFailed(_ref('a'), ImageStoreProblem.source);

      await queue.resumeInterrupted();

      final Map<String, DownloadQueueState> states =
          <String, DownloadQueueState>{
            for (final QueuedDownload e in await queue.entries())
              e.ref.id: e.state,
          };
      expect(states, <String, DownloadQueueState>{
        'a': DownloadQueueState.failed,
        'b': DownloadQueueState.pending,
      });
    });

    test(
      'a corrupt state cell reads as pending, so nothing is stranded',
      () async {
        // Fails towards *doing the work*: read as failed or running, a corrupt
        // row would sit in the queue forever with nothing willing to claim it.
        await queue.enqueue(_entries(<String>['a']));
        await db.customStatement(
          "UPDATE download_queue_entries SET state = 'gibberish' WHERE id = ?",
          <Object>['a'],
        );

        expect(
          (await queue.entries()).single.state,
          DownloadQueueState.pending,
        );
      },
    );

    test(
      'a corrupt failure cell stays a failure, with an unknown why',
      () async {
        await queue.enqueue(_entries(<String>['a']));
        await db.customStatement(
          "UPDATE download_queue_entries SET state = 'failed', "
          "failure = 'gibberish' WHERE id = ?",
          <Object>['a'],
        );

        final QueuedDownload entry = (await queue.entries()).single;
        expect(entry.state, DownloadQueueState.failed);
        expect(entry.failure, ImageStoreProblem.unknown);
      },
    );

    test('two sources issuing the same id are two entries', () async {
      await queue.enqueue(<QueuedDownload>[
        _entry('12345'),
        _entry('12345', source: SourceId.konachan),
      ]);

      expect(await queue.entries(), hasLength(2));
    });
  });
}

List<QueuedDownload> _entries(List<String> ids) => <QueuedDownload>[
  for (final (int index, String id) in ids.indexed) _entry(id, at: index),
];

QueuedDownload _entry(
  String id, {
  int at = 0,
  Purity purity = Purity.sfw,
  StorageTier? tier,
  SourceId source = SourceId.wallhaven,
}) => QueuedDownload(
  wallpaper: _wallpaper(id, purity: purity, source: source),
  tier: tier,
  queuedAt: DateTime.utc(2026, 7, 26).add(Duration(seconds: at)),
);

WallpaperRef _ref(String id) => WallpaperRef(SourceId.wallhaven, id);

Wallpaper _wallpaper(
  String id, {
  required Purity purity,
  required SourceId source,
}) => Wallpaper(
  id: id,
  source: source,
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
  fullImageUrl: 'https://w.wallhaven.cc/full/xx/wallhaven-$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/xx/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/xx/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/xx/$id.jpg',
  resolution: const Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: purity,
  category: Category.general,
  colors: const <String>[],
);
