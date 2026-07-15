import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/storage/method_channel_local_preview_cache.dart';
import 'package:tela/domain/models/local_preview.dart';

void main() {
  group("MethodChannelLocalPreviewCache resolves a download's location", () {
    test(
      'reads a file: location directly, without the native channel',
      () async {
        final List<String> calls = <String>[];
        final MethodChannelLocalPreviewCache cache =
            MethodChannelLocalPreviewCache(
              invokeMethod:
                  (String method, Map<String, String> arguments) async {
                    calls.add(method);
                    return null;
                  },
            );

        final LocalPreview? preview = await cache.materialize(
          Uri.file('/storage/emulated/0/Pictures/tela/wallhaven-e7jvjd.jpg'),
        );

        expect(preview, isNotNull);
        expect(preview!.isTemporary, isFalse);
        expect(
          preview.path,
          '/storage/emulated/0/Pictures/tela/wallhaven-e7jvjd.jpg',
        );
        // A file the user already owns must never be copied — nor released.
        expect(calls, isEmpty);
      },
    );

    test(
      'materialises a MediaStore content: URI into a temporary file',
      () async {
        final MethodChannelLocalPreviewCache cache =
            MethodChannelLocalPreviewCache(
              invokeMethod:
                  (String method, Map<String, String> arguments) async {
                    expect(method, 'materializeImage');
                    expect(
                      arguments['location'],
                      'content://media/external/images/media/42',
                    );
                    return <Object?, Object?>{
                      'success': true,
                      'path': '/cache/previews/preview-1',
                    };
                  },
            );

        final LocalPreview? preview = await cache.materialize(
          Uri.parse('content://media/external/images/media/42'),
        );

        expect(preview, isNotNull);
        expect(preview!.isTemporary, isTrue);
        expect(preview.path, '/cache/previews/preview-1');
      },
    );

    test('materialises a SAF document URI into a temporary file', () async {
      final MethodChannelLocalPreviewCache cache =
          MethodChannelLocalPreviewCache(
            invokeMethod:
                (String method, Map<String, String> arguments) async =>
                    <Object?, Object?>{
                      'success': true,
                      'path': '/cache/previews/preview-2',
                    },
          );

      final LocalPreview? preview = await cache.materialize(
        Uri.parse(
          'content://com.android.externalstorage.documents/tree/primary%3Atela/document/primary%3Atela%2Fwallhaven-7j1mzo.jpg',
        ),
      );

      expect(preview, isNotNull);
      expect(preview!.isTemporary, isTrue);
      expect(preview.path, '/cache/previews/preview-2');
    });

    test('answers null when native cannot read the location', () async {
      final MethodChannelLocalPreviewCache cache =
          MethodChannelLocalPreviewCache(
            invokeMethod:
                (String method, Map<String, String> arguments) async =>
                    <Object?, Object?>{'success': false},
          );

      final LocalPreview? preview = await cache.materialize(
        Uri.parse('content://media/external/images/media/99'),
      );

      expect(preview, isNull);
    });
  });

  group('MethodChannelLocalPreviewCache release', () {
    test('deletes a temporary copy through the channel', () async {
      final List<Map<String, String>> calls = <Map<String, String>>[];
      final MethodChannelLocalPreviewCache cache =
          MethodChannelLocalPreviewCache(
            invokeMethod: (String method, Map<String, String> arguments) async {
              calls.add(<String, String>{'method': method, ...arguments});
              return null;
            },
          );

      await cache.release(
        const LocalPreview(
          path: '/cache/previews/preview-1',
          isTemporary: true,
        ),
      );

      expect(calls, hasLength(1));
      expect(calls.single['method'], 'releasePreview');
      expect(calls.single['path'], '/cache/previews/preview-1');
    });

    test(
      "never touches a non-temporary preview — that is the user's file",
      () async {
        final List<String> calls = <String>[];
        final MethodChannelLocalPreviewCache cache =
            MethodChannelLocalPreviewCache(
              invokeMethod:
                  (String method, Map<String, String> arguments) async {
                    calls.add(method);
                    return null;
                  },
            );

        await cache.release(
          const LocalPreview(path: '/pictures/tela/x.jpg', isTemporary: false),
        );

        expect(calls, isEmpty);
      },
    );
  });
}
