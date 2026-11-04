import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/transfer_pace.dart';

void main() {
  TransferPace pace(int done, int total, Duration elapsed) =>
      TransferPace(done: done, total: total, elapsed: elapsed);

  test('the fraction is done over total', () {
    expect(pace(25, 100, Duration.zero).fraction, 0.25);
  });

  test('the fraction is 0 with nothing to measure and never above 1', () {
    expect(pace(5, 0, Duration.zero).fraction, 0);
    expect(pace(150, 100, Duration.zero).fraction, 1);
  });

  test('the speed averages the whole run', () {
    final TransferPace ten = pace(1000, 4000, const Duration(seconds: 10));

    expect(ten.perSecond, 100);
    expect(ten.remaining, const Duration(seconds: 30));
  });

  /// The first files include folder creation on an empty card, so the rate
  /// they imply is the one number guaranteed to be wrong.
  test('no estimate before the run has settled', () {
    final TransferPace early = pace(1000, 4000, const Duration(seconds: 2));

    expect(early.perSecond, isNull);
    expect(early.remaining, isNull);
  });

  test('no estimate while nothing is done', () {
    expect(pace(0, 4000, const Duration(minutes: 1)).remaining, isNull);
  });

  test('time left rounds up to the whole second and never goes negative', () {
    expect(
      pace(3, 10, const Duration(seconds: 6)).remaining,
      const Duration(seconds: 14),
    );
    expect(pace(12, 10, const Duration(seconds: 6)).remaining, Duration.zero);
  });
}
