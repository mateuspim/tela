import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/storage/method_channel_image_store.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';

void main() {
  test('sends image identity, purity, and tier to the native store', () async {
    final _FakeImageStoreChannel fake = _FakeImageStoreChannel();
    final MethodChannelImageStore store = MethodChannelImageStore(
      invokeMethod: fake.call,
    );

    await store.store(
      id: 'e7jvjd',
      imageUrl: _imageUrl,
      purity: Purity.nsfw,
      tier: StorageTier.appPrivate,
    );

    expect(fake.receivedMethod, 'storeImage');
    expect(fake.receivedArguments, <String, String>{
      'id': 'e7jvjd',
      'imageUrl': _imageUrl,
      'purity': 'nsfw',
      'tier': 'appPrivate',
    });
  });

  test('maps native failures without retaining a sensitive location', () async {
    const Map<String, ImageStoreProblem> cases = <String, ImageStoreProblem>{
      'downloadFailed': ImageStoreProblem.source,
      'unavailable': ImageStoreProblem.unavailable,
      'notConfigured': ImageStoreProblem.notConfigured,
      'restricted': ImageStoreProblem.restricted,
      'newNativeFailure': ImageStoreProblem.unknown,
    };

    for (final MapEntry<String, ImageStoreProblem> entry in cases.entries) {
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel(
        response: <Object?, Object?>{
          'success': false,
          'errorCode': entry.key,
          'unsafeDebugValue': _imageUrl,
        },
      );
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: fake.call,
      );

      await expectLater(
        store.store(
          id: 'e7jvjd',
          imageUrl: _imageUrl,
          purity: Purity.nsfw,
          tier: StorageTier.sharedGallery,
        ),
        throwsA(_failureWith(entry.value)),
      );
    }
  });

  test('maps a platform exception to a safe storage failure', () async {
    final MethodChannelImageStore store = MethodChannelImageStore(
      invokeMethod: _FakeImageStoreChannel(
        platformError: PlatformException(code: 'notConfigured'),
      ).call,
    );

    await expectLater(
      store.store(
        id: 'e7jvjd',
        imageUrl: _imageUrl,
        purity: Purity.sfw,
        tier: StorageTier.filesOutsideGallery,
      ),
      throwsA(_failureWith(ImageStoreProblem.notConfigured)),
    );
  });

  group('privateImages', () {
    test('maps the native listing into domain images', () async {
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel(
        response: <Object?, Object?>{
          'success': true,
          'images': <Object?>[
            <Object?, Object?>{
              'id': 'e7jvjd',
              'location': 'file:///data/user/0/cc.pym.tela/files/w-e7jvjd.jpg',
              'savedAt': 1750000000000,
              'sizeBytes': 2048,
            },
          ],
        },
      );
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: fake.call,
      );

      final List<PrivateImage> images = await store.privateImages();

      expect(fake.receivedMethod, 'listPrivateImages');
      expect(images.single.id, 'e7jvjd');
      expect(images.single.sizeBytes, 2048);
      expect(
        images.single.savedAt,
        DateTime.fromMillisecondsSinceEpoch(1750000000000),
      );
    });

    test('an empty tier lists nothing rather than failing', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{'success': true, 'images': <Object?>[]},
        ).call,
      );

      expect(await store.privateImages(), isEmpty);
    });

    test('skips a mangled entry instead of emptying the library', () async {
      // One unreadable row must not read as "all my files are gone".
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{
            'success': true,
            'images': <Object?>[
              <Object?, Object?>{'id': 'broken'},
              <Object?, Object?>{
                'id': 'intact',
                'location': 'file:///files/w-intact.jpg',
                'savedAt': 1750000000000,
                'sizeBytes': 1,
              },
            ],
          },
        ).call,
      );

      final List<PrivateImage> images = await store.privateImages();

      expect(images.map((PrivateImage image) => image.id), <String>['intact']);
    });

    test('maps a native listing failure to a safe failure', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{
            'success': false,
            'errorCode': 'unavailable',
          },
        ).call,
      );

      await expectLater(
        store.privateImages(),
        throwsA(_failureWith(ImageStoreProblem.unavailable)),
      );
    });
  });

  group('deletePrivateImage', () {
    test('sends the id to the native delete', () async {
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel(
        response: <Object?, Object?>{'success': true},
      );
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: fake.call,
      );

      await store.deletePrivateImage('e7jvjd');

      expect(fake.receivedMethod, 'deletePrivateImage');
      expect(fake.receivedArguments, <String, String>{'id': 'e7jvjd'});
    });

    test('maps a refused delete to a safe failure', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{
            'success': false,
            'errorCode': 'unavailable',
          },
        ).call,
      );

      await expectLater(
        store.deletePrivateImage('e7jvjd'),
        throwsA(_failureWith(ImageStoreProblem.unavailable)),
      );
    });
  });

  group('canRead', () {
    test('asks the native side about the location', () async {
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel(
        response: <Object?, Object?>{'success': true, 'readable': true},
      );
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: fake.call,
      );

      expect(await store.canRead(Uri.parse('content://media/images/42')), true);
      expect(fake.receivedMethod, 'canReadImage');
      expect(fake.receivedArguments, <String, String>{
        'location': 'content://media/images/42',
      });
    });

    test('a file that will not open reads as gone', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{'success': true, 'readable': false},
        ).call,
      );

      expect(await store.canRead(Uri.parse('file:///gone.jpg')), false);
    });

    test('a native error costs the badge, not the screen', () async {
      // The one caller draws a tile with this. A history row whose file is gone
      // still sets its wallpaper by re-fetching, so a probe that blows up must
      // never take the download history down with it — and "unreadable" is the
      // safe guess anyway: at worst it warns about a file that is still there.
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          platformError: PlatformException(code: 'unavailable'),
        ).call,
      );

      expect(await store.canRead(Uri.parse('file:///gone.jpg')), false);
    });
  });
}

Matcher _failureWith(ImageStoreProblem problem) {
  return isA<ImageStoreFailure>()
      .having(
        (ImageStoreFailure failure) => failure.problem,
        'problem',
        problem,
      )
      .having(
        (ImageStoreFailure failure) => failure.toString(),
        'safe text',
        isNot(contains(_imageUrl)),
      );
}

const String _imageUrl = 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg';

class _FakeImageStoreChannel {
  _FakeImageStoreChannel({
    this.response = const <Object?, Object?>{
      'success': true,
      'location': 'content://cc.pym.tela/image/e7jvjd',
    },
    this.platformError,
  });

  final Object? response;
  final PlatformException? platformError;
  String? receivedMethod;
  Map<String, String>? receivedArguments;

  Future<Object?> call(String method, Map<String, String> arguments) async {
    receivedMethod = method;
    receivedArguments = arguments;
    final PlatformException? toThrow = platformError;
    if (toThrow != null) throw toThrow;
    return response;
  }
}
