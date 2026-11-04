/// Runs every step in order, even if an earlier one throws, and returns how
/// many failed.
///
/// For cleanup that must not stop halfway: clearing a web view's cookies,
/// cache and storage run from a screen's `dispose`, where a platform view that
/// is already gone makes some steps throw. Errors are swallowed on purpose —
/// nobody is left to show them to — and the count lets a caller or test see it.
///
/// ```dart
/// final int failed = await runIndependently(<Future<void> Function()>[a, b]);
/// ```
Future<int> runIndependently(List<Future<void> Function()> steps) async {
  int failed = 0;
  for (final Future<void> Function() step in steps) {
    try {
      await step();
    } on Object {
      failed++;
    }
  }
  return failed;
}
