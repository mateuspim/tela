import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/wallpaper/method_channel_wallpaper_rotation.dart';
import 'package:tela/domain/models/rotation_plan.dart';
import 'package:tela/domain/models/wallpaper_target.dart';

/// Answers the rotation channel with [answer] and records every call.
class _FakeRotationChannel {
  _FakeRotationChannel({this.answer});

  /// What `current` comes back with.
  final Map<Object?, Object?>? answer;

  final List<MethodCall> calls = <MethodCall>[];

  MethodChannel install() {
    const MethodChannel channel = MethodChannel('cc.pym.tela/rotation');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return call.method == 'current' ? answer : null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    return channel;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sends the plan as the three values the schedule needs', () async {
    final _FakeRotationChannel fake = _FakeRotationChannel();
    final MethodChannelWallpaperRotation rotation =
        MethodChannelWallpaperRotation(fake.install());

    await rotation.start(
      const RotationPlan(
        interval: RotationInterval.hourly,
        source: RotationSource.privateLibrary,
        target: WallpaperTarget.both,
      ),
    );

    expect(fake.calls.single.method, 'start');
    expect(fake.calls.single.arguments, <String, Object?>{
      'intervalMinutes': 60,
      'tier': 'appPrivate',
      'target': 'both',
    });
  });

  test('never sends the SAF tree or vault label', () async {
    // They live in native preferences and the worker reads them at run time —
    // a schedule made months ago must follow a vault the user has since moved,
    // not a copy frozen on the day it was made.
    final _FakeRotationChannel fake = _FakeRotationChannel();
    final MethodChannelWallpaperRotation rotation =
        MethodChannelWallpaperRotation(fake.install());

    await rotation.start(RotationPlan.defaults);

    final Map<Object?, Object?> arguments =
        fake.calls.single.arguments as Map<Object?, Object?>;
    expect(arguments.containsKey('tree'), isFalse);
    expect(arguments.containsKey('vaultLabel'), isFalse);
  });

  test('reads a running schedule back', () async {
    final _FakeRotationChannel fake = _FakeRotationChannel(
      answer: <Object?, Object?>{
        'intervalMinutes': 1440,
        'tier': 'sharedGallery',
        'target': 'home',
      },
    );
    final MethodChannelWallpaperRotation rotation =
        MethodChannelWallpaperRotation(fake.install());

    expect(await rotation.current(), RotationPlan.defaults);
  });

  test('reads no schedule as off', () async {
    final _FakeRotationChannel fake = _FakeRotationChannel();
    final MethodChannelWallpaperRotation rotation =
        MethodChannelWallpaperRotation(fake.install());

    expect(await rotation.current(), isNull);
  });

  test('reads a schedule it cannot describe as off', () async {
    // A tier or interval from a build this one does not know. Claiming
    // rotation is off is the safer of the two wrong answers: the user's next
    // toggle re-enqueues it either way, where a fallback plan would misreport
    // what the platform is actually doing.
    final _FakeRotationChannel fake = _FakeRotationChannel(
      answer: <Object?, Object?>{
        'intervalMinutes': 7,
        'tier': 'dropbox',
        'target': 'home',
      },
    );
    final MethodChannelWallpaperRotation rotation =
        MethodChannelWallpaperRotation(fake.install());

    expect(await rotation.current(), isNull);
  });

  test('stops without arguments', () async {
    final _FakeRotationChannel fake = _FakeRotationChannel();
    final MethodChannelWallpaperRotation rotation =
        MethodChannelWallpaperRotation(fake.install());

    await rotation.stop();

    expect(fake.calls.single.method, 'stop');
  });
}
