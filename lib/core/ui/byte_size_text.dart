/// Renders [bytes] the way a storage screen does: `0 B`, `12 KB`, `1.9 GB`.
///
/// One decimal place from MB up, and none below: "1.9 GB" is the number that
/// makes someone press the button, and "1.9 KB" of precision on a rounding
/// error is noise.
///
/// ```dart
/// formatBytes(2040109465); // '1.9 GB'
/// ```
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const List<String> units = <String>['KB', 'MB', 'GB', 'TB'];
  double size = bytes / 1024;
  int unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final String rendered = unit == 0
      ? size.round().toString()
      : size.toStringAsFixed(1);
  return '$rendered ${units[unit]}';
}
