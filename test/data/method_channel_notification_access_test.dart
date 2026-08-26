import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/notifications/method_channel_notification_access.dart';

void main() {
  group('reading whether notifications are on', () {
    test('reports what the platform answers', () async {
      final _FakeChannel fake = _FakeChannel(
        response: <Object?, Object?>{'enabled': true},
      );

      expect(await _access(fake).areEnabled(), isTrue);
      expect(fake.methods, <String>['areEnabled']);
    });

    /// Off is the safe guess: the row then offers the way to fix it, which
    /// is harmless when they were on and the only useful answer when not.
    test('a platform failure reads as off, never as on', () async {
      final MethodChannelNotificationAccess access = _access(
        _FakeChannel(throws: PlatformException(code: 'unavailable')),
      );

      expect(await access.areEnabled(), isFalse);
    });

    /// The channel lives on the activity, so a call with no screen attached
    /// throws this rather than a PlatformException. It must not escape either.
    test('a missing screen reads as off, not as a crash', () async {
      final MethodChannelNotificationAccess access = _access(
        _FakeChannel(throws: MissingPluginException('no activity')),
      );

      expect(await access.areEnabled(), isFalse);
    });

    test('a mangled answer reads as off', () async {
      final MethodChannelNotificationAccess access = _access(
        _FakeChannel(response: 'yes'),
      );

      expect(await access.areEnabled(), isFalse);
    });
  });

  group('opening Android’s own page', () {
    test('reports that it opened', () async {
      final _FakeChannel fake = _FakeChannel(
        response: <Object?, Object?>{'opened': true},
      );

      expect(await _access(fake).openSettings(), isTrue);
      expect(fake.methods, <String>['openSettings']);
    });

    /// A device with no settings activity answers false, and the row says so
    /// rather than leaving the user waiting for a page that never arrives.
    test('a device that cannot open it answers false', () async {
      final MethodChannelNotificationAccess access = _access(
        _FakeChannel(response: <Object?, Object?>{'opened': false}),
      );

      expect(await access.openSettings(), isFalse);
    });
  });
}

MethodChannelNotificationAccess _access(_FakeChannel fake) =>
    MethodChannelNotificationAccess(invokeMethod: fake.call);

class _FakeChannel {
  _FakeChannel({this.response, this.throws});

  final Object? response;
  final Exception? throws;
  final List<String> methods = <String>[];

  Future<Object?> call(String method) async {
    methods.add(method);
    final Exception? toThrow = throws;
    if (toThrow != null) throw toThrow;
    return response;
  }
}
