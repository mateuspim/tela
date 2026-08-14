import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/wallpaper/method_channel_wallpaper_sharer.dart';
import 'package:tela/domain/models/clipboard_confirmation.dart';
import 'package:tela/domain/models/wallpaper_share_failure.dart';

void main() {
  test('shareLink sends the page URL to the native method', () async {
    final _FakeShareChannel fake = _FakeShareChannel();
    final MethodChannelWallpaperSharer sharer = MethodChannelWallpaperSharer(
      invokeMethod: fake.call,
    );

    await sharer.shareLink(Uri.parse(_page));

    expect(fake.receivedMethods, <String>['shareLink']);
    expect(fake.receivedArguments.single['page'], _page);
  });

  test(
    'shareImage sends the source and file name to the native method',
    () async {
      final _FakeShareChannel fake = _FakeShareChannel();
      final MethodChannelWallpaperSharer sharer = MethodChannelWallpaperSharer(
        invokeMethod: fake.call,
      );

      await sharer.shareImage(
        source: Uri.parse(_imageUrl),
        fileName: 'wallhaven-e7jvjd.jpg',
      );

      expect(fake.receivedMethods, <String>['shareImage']);
      expect(fake.receivedArguments.single['source'], _imageUrl);
      expect(fake.receivedArguments.single['fileName'], 'wallhaven-e7jvjd.jpg');
    },
  );

  test(
    'copyImage sends the source and file name to the native method',
    () async {
      final _FakeShareChannel fake = _FakeShareChannel();
      final MethodChannelWallpaperSharer sharer = MethodChannelWallpaperSharer(
        invokeMethod: fake.call,
      );

      await sharer.copyImage(
        source: Uri.parse(_imageUrl),
        fileName: 'wallhaven-e7jvjd.jpg',
        sensitive: false,
      );

      expect(fake.receivedMethods, <String>['copyImage']);
      expect(fake.receivedArguments.single['source'], _imageUrl);
      expect(fake.receivedArguments.single['fileName'], 'wallhaven-e7jvjd.jpg');
      expect(fake.receivedArguments.single['sensitive'], 'false');
    },
  );

  test('copyImage stays quiet when Android showed its own notice', () async {
    final _FakeShareChannel fake = _FakeShareChannel(
      response: <Object?, Object?>{'success': true, 'systemNotice': true},
    );
    final MethodChannelWallpaperSharer sharer = MethodChannelWallpaperSharer(
      invokeMethod: fake.call,
    );

    expect(
      await sharer.copyImage(
        source: Uri.parse(_imageUrl),
        fileName: 'a.jpg',
        sensitive: false,
      ),
      ClipboardConfirmation.system,
    );
  });

  test('copyImage confirms it itself when the notice is absent', () async {
    // Below Android 13 nothing is shown, and a response tela cannot read is
    // treated the same way: a silent copy looks exactly like a failed one.
    for (final Object? response in <Object?>[
      <Object?, Object?>{'success': true, 'systemNotice': false},
      <Object?, Object?>{'success': true},
    ]) {
      final MethodChannelWallpaperSharer sharer = MethodChannelWallpaperSharer(
        invokeMethod: _FakeShareChannel(response: response).call,
      );

      expect(
        await sharer.copyImage(
          source: Uri.parse(_imageUrl),
          fileName: 'a.jpg',
          sensitive: false,
        ),
        ClipboardConfirmation.tela,
      );
    }
  });

  test('a failed copy throws rather than reporting a confirmation', () async {
    final _FakeShareChannel fake = _FakeShareChannel(
      response: <Object?, Object?>{
        'success': false,
        'errorCode': 'downloadFailed',
      },
    );
    final MethodChannelWallpaperSharer sharer = MethodChannelWallpaperSharer(
      invokeMethod: fake.call,
    );

    await expectLater(
      sharer.copyImage(
        source: Uri.parse(_imageUrl),
        fileName: 'a.jpg',
        sensitive: false,
      ),
      throwsA(_failureWith(WallpaperShareProblem.source)),
    );
  });

  test('maps native error codes without retaining the image URL', () async {
    const Map<String, WallpaperShareProblem> cases =
        <String, WallpaperShareProblem>{
          'downloadFailed': WallpaperShareProblem.source,
          'noTarget': WallpaperShareProblem.unavailable,
          'newNativeFailure': WallpaperShareProblem.unknown,
        };

    for (final MapEntry<String, WallpaperShareProblem> entry in cases.entries) {
      final _FakeShareChannel fake = _FakeShareChannel(
        response: <Object?, Object?>{
          'success': false,
          'errorCode': entry.key,
          'unsafeDebugValue': _imageUrl,
        },
      );
      final MethodChannelWallpaperSharer sharer = MethodChannelWallpaperSharer(
        invokeMethod: fake.call,
      );

      await expectLater(
        sharer.shareImage(
          source: Uri.parse(_imageUrl),
          fileName: 'wallhaven-e7jvjd.jpg',
        ),
        throwsA(_failureWith(entry.value)),
      );
    }
  });

  test('maps a platform exception to a safe domain failure', () async {
    final _FakeShareChannel fake = _FakeShareChannel(
      platformError: PlatformException(code: 'noTarget'),
    );
    final MethodChannelWallpaperSharer sharer = MethodChannelWallpaperSharer(
      invokeMethod: fake.call,
    );

    await expectLater(
      sharer.shareLink(Uri.parse(_page)),
      throwsA(_failureWith(WallpaperShareProblem.unavailable)),
    );
  });
}

Matcher _failureWith(WallpaperShareProblem problem) {
  return isA<WallpaperShareFailure>()
      .having(
        (WallpaperShareFailure failure) => failure.problem,
        'problem',
        problem,
      )
      .having(
        (WallpaperShareFailure failure) => failure.toString(),
        'safe text',
        isNot(contains(_imageUrl)),
      );
}

const String _page = 'https://wallhaven.cc/w/e7jvjd';
const String _imageUrl = 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg';

class _FakeShareChannel {
  _FakeShareChannel({
    this.response = const <Object?, Object?>{'success': true},
    this.platformError,
  });

  final Object? response;
  final PlatformException? platformError;
  final List<String> receivedMethods = <String>[];
  final List<Map<String, String>> receivedArguments = <Map<String, String>>[];

  Future<Object?> call(String method, Map<String, String> arguments) async {
    receivedMethods.add(method);
    receivedArguments.add(arguments);
    final PlatformException? toThrow = platformError;
    if (toThrow != null) throw toThrow;
    return response;
  }
}
