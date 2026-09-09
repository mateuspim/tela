import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/downloads/method_channel_download_queue_anchor.dart';

void main() {
  group('MethodChannelDownloadQueueAnchor', () {
    late List<String> calls;
    late List<Map<String, String>> arguments;
    late bool nativeAccepts;
    late MethodChannelDownloadQueueAnchor anchor;

    setUp(() {
      calls = <String>[];
      arguments = <Map<String, String>>[];
      nativeAccepts = true;
      anchor = MethodChannelDownloadQueueAnchor(
        invokeMethod: (String method, Map<String, String> args) async {
          calls.add(method);
          arguments.add(args);
          return nativeAccepts;
        },
      );
    });

    test('sends the words it was given', () async {
      expect(
        await anchor.hold(title: 'Downloading wallpapers', body: '7 left'),
        isTrue,
      );

      expect(calls, <String>['anchor']);
      expect(arguments.single, <String, String>{
        'title': 'Downloading wallpapers',
        'body': '7 left',
      });
    });

    // The queue republishes after every settled entry. Without this the shade
    // would be re-posted several times a second through a batch, and the
    // service told to start over for a notification that had not changed.
    test('repeats nothing across the channel', () async {
      await anchor.hold(title: 'Downloading wallpapers', body: '7 left');
      await anchor.hold(title: 'Downloading wallpapers', body: '7 left');
      await anchor.hold(title: 'Downloading wallpapers', body: '7 left');

      expect(calls, <String>['anchor']);
    });

    test('a changed count does cross', () async {
      await anchor.hold(title: 'Downloading wallpapers', body: '7 left');
      await anchor.hold(title: 'Downloading wallpapers', body: '6 left');

      expect(calls, <String>['anchor', 'anchor']);
      expect(arguments.last['body'], '6 left');
    });

    test('releasing an anchor that is up crosses once', () async {
      await anchor.hold(title: 'Downloading wallpapers', body: '7 left');
      await anchor.release();
      await anchor.release();

      expect(calls, <String>['anchor', 'release']);
    });

    test(
      'first release clears notification state left by a dead process',
      () async {
        await anchor.release();
        await anchor.release();

        expect(calls, <String>['release']);
      },
    );

    // The refusal is Android forbidding a foreground-service start from the
    // background, and it lifts the moment the user returns to the app. Caching
    // it would leave the queue permanently unanchored after one bad moment.
    test(
      'a refused hold is not remembered, so the next attempt retries',
      () async {
        nativeAccepts = false;
        expect(
          await anchor.hold(title: 'Downloading wallpapers', body: '7 left'),
          isFalse,
        );

        nativeAccepts = true;
        expect(
          await anchor.hold(title: 'Downloading wallpapers', body: '7 left'),
          isTrue,
        );
        expect(calls, <String>['anchor', 'anchor']);
      },
    );

    test('a native answer of null reads as refused', () async {
      anchor = MethodChannelDownloadQueueAnchor(
        invokeMethod: (String method, Map<String, String> args) async => null,
      );

      expect(
        await anchor.hold(title: 'Downloading wallpapers', body: '7 left'),
        isFalse,
      );
    });
  });
}
