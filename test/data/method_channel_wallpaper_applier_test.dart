import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/wallpaper/method_channel_wallpaper_applier.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';

void main() {
  test(
    'sends every domain target and full image to the native method',
    () async {
      final _FakeWallpaperChannel fake = _FakeWallpaperChannel();
      final MethodChannelWallpaperApplier applier =
          MethodChannelWallpaperApplier(
            invokeMethod: fake.call,
          );

      for (final WallpaperTarget target in WallpaperTarget.values) {
        await applier.apply(source: Uri.parse(_imageUrl), target: target);
      }

      expect(fake.receivedMethods, <String>[
        'applyWallpaper',
        'applyWallpaper',
        'applyWallpaper',
      ]);
      expect(
        fake.receivedArguments.map((arguments) => arguments['source']),
        <String>[_imageUrl, _imageUrl, _imageUrl],
      );
      expect(
        fake.receivedArguments.map((arguments) => arguments['target']),
        <String>['home', 'lock', 'both'],
      );
    },
  );

  test('maps native error codes without retaining the image URL', () async {
    const Map<String, WallpaperApplyProblem> cases =
        <String, WallpaperApplyProblem>{
          'downloadFailed': WallpaperApplyProblem.source,
          'sourceUnreadable': WallpaperApplyProblem.source,
          'unsupported': WallpaperApplyProblem.unsupported,
          'applyFailed': WallpaperApplyProblem.rejected,
          'newNativeFailure': WallpaperApplyProblem.unknown,
        };

    for (final MapEntry<String, WallpaperApplyProblem> entry in cases.entries) {
      final _FakeWallpaperChannel fake = _FakeWallpaperChannel(
        response: <Object?, Object?>{
          'success': false,
          'errorCode': entry.key,
          'unsafeDebugValue': _imageUrl,
        },
      );
      final MethodChannelWallpaperApplier applier =
          MethodChannelWallpaperApplier(invokeMethod: fake.call);

      await expectLater(
        applier.apply(
          source: Uri.parse(_imageUrl),
          target: WallpaperTarget.home,
        ),
        throwsA(_failureWith(entry.value)),
      );
    }
  });

  test('maps a platform exception to a safe domain failure', () async {
    final _FakeWallpaperChannel fake = _FakeWallpaperChannel(
      platformError: PlatformException(code: 'applyFailed'),
    );
    final MethodChannelWallpaperApplier applier = MethodChannelWallpaperApplier(
      invokeMethod: fake.call,
    );

    await expectLater(
      applier.apply(source: Uri.parse(_imageUrl), target: WallpaperTarget.lock),
      throwsA(_failureWith(WallpaperApplyProblem.rejected)),
    );
  });
}

Matcher _failureWith(WallpaperApplyProblem problem) {
  return isA<WallpaperApplyFailure>()
      .having(
        (WallpaperApplyFailure failure) => failure.problem,
        'problem',
        problem,
      )
      .having(
        (WallpaperApplyFailure failure) => failure.toString(),
        'safe text',
        isNot(contains(_imageUrl)),
      );
}

const String _imageUrl = 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg';

class _FakeWallpaperChannel {
  _FakeWallpaperChannel({
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
