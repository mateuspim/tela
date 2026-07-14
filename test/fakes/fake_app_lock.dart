import 'package:tela/domain/ports/app_lock.dart';

/// [AppLock] that answers however the test needs, without a real prompt.
class FakeAppLock implements AppLock {
  /// Creates a lock that is [available] and answers [outcome] when prompted.
  ///
  /// [passes] spells the common case short: it selects [AppLockOutcome.passed]
  /// or [AppLockOutcome.refused]. Give [outcome] directly for a lockout or an
  /// unaskable device — the two cases the old bool could never express, and the
  /// two the rules now turn on.
  FakeAppLock({
    this.available = true,
    bool passes = true,
    AppLockOutcome? outcome,
  }) : outcome =
           outcome ?? (passes ? AppLockOutcome.passed : AppLockOutcome.refused);

  /// Whether the device can ask for a biometric or PIN at all.
  final bool available;

  /// How the prompt ends.
  final AppLockOutcome outcome;

  /// How many times the prompt was raised.
  int prompts = 0;

  /// The reason shown by the last prompt.
  String? lastReason;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AppLockOutcome> authenticate({required String reason}) async {
    prompts++;
    lastReason = reason;
    return outcome;
  }
}
