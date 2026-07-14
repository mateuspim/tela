import 'package:tela/domain/ports/app_lock.dart';

/// [AppLock] that answers however the test needs, without a real prompt.
class FakeAppLock implements AppLock {
  /// Creates a lock that is [available] and answers [passes] when prompted.
  FakeAppLock({this.available = true, this.passes = true});

  /// Whether the device can ask for a biometric or PIN at all.
  final bool available;

  /// What the prompt answers.
  final bool passes;

  /// How many times the prompt was raised.
  int prompts = 0;

  /// The reason shown by the last prompt.
  String? lastReason;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({required String reason}) async {
    prompts++;
    lastReason = reason;
    return passes;
  }
}
