import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/web/independent_steps.dart';

void main() {
  test('a throwing step does not skip the ones after it', () async {
    final List<String> ran = <String>[];

    final int failed = await runIndependently(<Future<void> Function()>[
      () async => ran.add('cookies'),
      () async => throw StateError('view already disposed'),
      () async => ran.add('storage'),
    ]);

    expect(ran, <String>['cookies', 'storage']);
    expect(failed, 1);
  });

  test('no steps reports no failures', () async {
    expect(await runIndependently(<Future<void> Function()>[]), 0);
  });
}
