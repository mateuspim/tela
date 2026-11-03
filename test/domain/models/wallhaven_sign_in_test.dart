import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/wallhaven_sign_in.dart';

const String _key = 'AbCdEfGhIjKlMnOpQrStUvWxYz012345';

SignInStep _step(String url) => WallhavenSignIn.stepFor(Uri.parse(url));

void main() {
  group('stepFor', () {
    test('waits on the login and recovery pages', () {
      expect(_step('https://wallhaven.cc/login'), SignInStep.awaitCredentials);
      expect(
        _step('https://wallhaven.cc/password/reset'),
        SignInStep.awaitCredentials,
      );
      expect(
        _step('https://wallhaven.cc/register'),
        SignInStep.awaitCredentials,
      );
    });

    test('reads the key on Account settings', () {
      expect(
        _step('https://wallhaven.cc/settings/account'),
        SignInStep.readKey,
      );
    });

    test('heads for Account settings from anywhere else on Wallhaven', () {
      expect(_step('https://wallhaven.cc/'), SignInStep.openAccountSettings);
      expect(
        _step('https://wallhaven.cc/settings/browsing'),
        SignInStep.openAccountSettings,
      );
    });

    test('does nothing off Wallhaven', () {
      expect(_step('https://example.com/'), SignInStep.awaitCredentials);
    });
  });

  group('isWallhaven', () {
    test('allows wallhaven.cc over https only', () {
      expect(
        WallhavenSignIn.isWallhaven(Uri.parse('https://wallhaven.cc/')),
        isTrue,
      );
      expect(
        WallhavenSignIn.isWallhaven(Uri.parse('https://www.wallhaven.cc/x')),
        isTrue,
      );
      expect(
        WallhavenSignIn.isWallhaven(Uri.parse('http://wallhaven.cc/')),
        isFalse,
      );
      expect(
        WallhavenSignIn.isWallhaven(Uri.parse('https://wallhaven.cc.evil.io/')),
        isFalse,
      );
    });
  });

  group('keyFrom', () {
    test('takes a bare or JSON-quoted key', () {
      expect(WallhavenSignIn.keyFrom(_key), _key);
      expect(WallhavenSignIn.keyFrom('"$_key"'), _key);
      expect(WallhavenSignIn.keyFrom('  "$_key"\n'), _key);
    });

    test('finds nothing in an empty or null result', () {
      expect(WallhavenSignIn.keyFrom('""'), isNull);
      expect(WallhavenSignIn.keyFrom('null'), isNull);
    });

    test('never mistakes the 40-char CSRF token for the key', () {
      expect(WallhavenSignIn.keyFrom('a' * 40), isNull);
    });

    test('rejects anything but letters and digits', () {
      expect(WallhavenSignIn.keyFrom('${'a' * 31}-'), isNull);
    });
  });
}
