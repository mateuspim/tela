import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/storage/method_channel_screen_guard.dart';

void main() {
  test('turns the window secure on the first acquire only', () async {
    final _RecordingChannel channel = _RecordingChannel();
    final MethodChannelScreenGuard guard = MethodChannelScreenGuard(
      invokeMethod: channel.call,
    );

    await guard.setSecure(secure: true);
    await guard.setSecure(secure: true);

    // A second holder while already secure changes nothing on the window.
    expect(channel.secureValues, <bool>[true]);
  });

  test('keeps the window secure until the last holder releases', () async {
    // The load-bearing case: the grid and the viewer both hold FLAG_SECURE, and
    // the viewer popping must not strip it from the grid still behind it.
    final _RecordingChannel channel = _RecordingChannel();
    final MethodChannelScreenGuard guard = MethodChannelScreenGuard(
      invokeMethod: channel.call,
    );

    await guard.setSecure(secure: true); // grid
    await guard.setSecure(secure: true); // viewer
    await guard.setSecure(secure: false); // viewer leaves

    expect(channel.secureValues, <bool>[true]);

    await guard.setSecure(secure: false); // grid leaves

    expect(channel.secureValues, <bool>[true, false]);
  });

  test('a stray release below zero never toggles the window', () async {
    final _RecordingChannel channel = _RecordingChannel();
    final MethodChannelScreenGuard guard = MethodChannelScreenGuard(
      invokeMethod: channel.call,
    );

    await guard.setSecure(secure: false);

    expect(channel.secureValues, isEmpty);
  });
}

/// Records the `secure` value of every call that actually crossed the channel.
class _RecordingChannel {
  final List<bool> secureValues = <bool>[];

  Future<void> call(String method, Map<String, bool> arguments) async {
    expect(method, 'setSecure');
    secureValues.add(arguments['secure']!);
  }
}
