import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/web/sign_in_browser_state.dart';

void main() {
  test('a progress tick after the page settled is dropped', () {
    final SignInStateGate gate = SignInStateGate();
    expect(gate.admit(const SignInLoading(0.5)), isA<SignInLoading>());
    expect(gate.admit(const SignInReady()), isA<SignInReady>());

    expect(gate.admit(const SignInLoading(1)), isNull);
  });

  test('a missing-key or failed state also resists late ticks', () {
    final SignInStateGate gate = SignInStateGate()
      ..admit(const SignInMissingKey());
    expect(gate.admit(const SignInLoading(1)), isNull);

    gate.admit(const SignInFailed());
    expect(gate.failed, isTrue);
    expect(gate.admit(const SignInLoading(1)), isNull);
  });

  test('a new page start lets loading through again', () {
    final SignInStateGate gate = SignInStateGate()
      ..admit(const SignInFailed())
      ..reset();

    expect(gate.failed, isFalse);
    expect(gate.admit(const SignInLoading(0)), isA<SignInLoading>());
  });
}
