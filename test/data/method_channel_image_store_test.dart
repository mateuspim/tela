import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/storage/method_channel_image_store.dart';
import 'package:tela/domain/models/image_store_failure.dart';
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
