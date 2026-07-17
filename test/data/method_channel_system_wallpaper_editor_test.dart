import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/wallpaper/method_channel_system_wallpaper_editor.dart';
import 'package:tela/domain/models/wallpaper_adjust_failure.dart';

void main() {
  test('openFor sends the source and file name to the native method', () async {
    final _FakeAdjustChannel fake = _FakeAdjustChannel();
    final MethodChannelSystemWallpaperEditor editor =
        MethodChannelSystemWallpaperEditor(invokeMethod: fake.call);

    await editor.openFor(
      source: Uri.parse(_imageUrl),
      fileName: 'wallhaven-e7jvjd.jpg',
    );

    expect(fake.receivedMethods, <String>['adjustWallpaper']);
    expect(fake.receivedArguments.single['source'], _imageUrl);
    expect(fake.receivedArguments.single['fileName'], 'wallhaven-e7jvjd.jpg');
  });

  test('maps native error codes without retaining the image URL', () async {
    const Map<String, WallpaperAdjustProblem> cases =
        <String, WallpaperAdjustProblem>{
          'downloadFailed': WallpaperAdjustProblem.source,
          'noEditor': WallpaperAdjustProblem.unavailable,
          'unsupportedImage': WallpaperAdjustProblem.unsupportedImage,
          'newNativeFailure': WallpaperAdjustProblem.unknown,
        };

    for (final MapEntry<String, WallpaperAdjustProblem> entry
        in cases.entries) {
      final _FakeAdjustChannel fake = _FakeAdjustChannel(
        response: <Object?, Object?>{
          'success': false,
          'errorCode': entry.key,
          'unsafeDebugValue': _imageUrl,
        },
      );
      final MethodChannelSystemWallpaperEditor editor =
          MethodChannelSystemWallpaperEditor(invokeMethod: fake.call);

      await expectLater(
        editor.openFor(
          source: Uri.parse(_imageUrl),
          fileName: 'wallhaven-e7jvjd.jpg',
        ),
        throwsA(_failureWith(entry.value)),
      );
    }
  });

  test('maps a platform exception to a safe domain failure', () async {
    final _FakeAdjustChannel fake = _FakeAdjustChannel(
      platformError: PlatformException(code: 'noEditor', message: _imageUrl),
    );
    final MethodChannelSystemWallpaperEditor editor =
        MethodChannelSystemWallpaperEditor(invokeMethod: fake.call);

    await expectLater(
      editor.openFor(
        source: Uri.parse(_imageUrl),
        fileName: 'wallhaven-e7jvjd.jpg',
      ),
      throwsA(_failureWith(WallpaperAdjustProblem.unavailable)),
    );
  });

  test('a response that is not a success map is an unknown failure', () async {
    // The editor answers a map or nothing; anything else means the native side
    // changed shape, and guessing "it worked" would silently swallow that.
    final _FakeAdjustChannel fake = _FakeAdjustChannel(response: null);
    final MethodChannelSystemWallpaperEditor editor =
        MethodChannelSystemWallpaperEditor(invokeMethod: fake.call);

    await expectLater(
      editor.openFor(
        source: Uri.parse(_imageUrl),
        fileName: 'wallhaven-e7jvjd.jpg',
      ),
      throwsA(_failureWith(WallpaperAdjustProblem.unknown)),
    );
  });

  test('a success map throws nothing', () async {
    final _FakeAdjustChannel fake = _FakeAdjustChannel();
    final MethodChannelSystemWallpaperEditor editor =
        MethodChannelSystemWallpaperEditor(invokeMethod: fake.call);

    await expectLater(
      editor.openFor(
        source: Uri.parse(_imageUrl),
        fileName: 'wallhaven-e7jvjd.jpg',
      ),
      completes,
    );
  });
}

Matcher _failureWith(WallpaperAdjustProblem problem) {
  return isA<WallpaperAdjustFailure>()
      .having(
        (WallpaperAdjustFailure failure) => failure.problem,
        'problem',
        problem,
      )
      .having(
        (WallpaperAdjustFailure failure) => failure.toString(),
        'safe text',
        isNot(contains(_imageUrl)),
      );
}

const String _imageUrl = 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg';

class _FakeAdjustChannel {
  _FakeAdjustChannel({
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
