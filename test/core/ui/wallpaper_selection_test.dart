import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/wallpaper_selection.dart';

/// D4 — the selection model itself, as plain Dart.
///
/// The widget behaviour it drives is pinned in
/// `test/features/browse_multi_select_test.dart`; this is only the state
/// machine, whose one interesting property is that it has no mode flag.
void main() {
  test('a fresh selection is inactive and empty', () {
    final WallpaperSelection selection = WallpaperSelection();

    expect(selection.isActive, isFalse);
    expect(selection.count, 0);
  });

  test('selectOnly enters the mode with exactly one tick', () {
    final WallpaperSelection selection = WallpaperSelection()
      ..selectOnly('e7jvjd')
      ..selectOnly('7j1mzo');

    expect(selection.isActive, isTrue);
    expect(selection.ids, <String>{'7j1mzo'});
  });

  test('unticking everything stays in the mode, and only clear leaves', () {
    // The trade the app-bar *Select* button bought. The mode used to be derived
    // from the ticks, so unticking the last tile left it — but a Select button
    // has no tile to tick, so under that rule pressing it did nothing at all.
    // The friendlier half: a mis-tap on your last tick no longer throws the
    // whole mode away with it.
    final WallpaperSelection selection = WallpaperSelection()
      ..selectOnly('e7jvjd')
      ..toggle('7j1mzo');
    expect(selection.count, 2);

    selection
      ..toggle('7j1mzo')
      ..toggle('e7jvjd');

    expect(selection.count, 0);
    expect(selection.isActive, isTrue);

    selection.clear();
    expect(selection.isActive, isFalse);
  });

  test('enter starts the mode with nothing ticked', () {
    // What the app-bar button does, and the case a derived mode cannot express.
    final WallpaperSelection selection = WallpaperSelection()..enter();

    expect(selection.isActive, isTrue);
    expect(selection.count, 0);
  });

  test('addAll notifies once, and not at all when nothing is new', () {
    int notifications = 0;
    // The listener attaches after the entry tick, so `selectOnly` is not one
    // of the notifications being counted.
    final WallpaperSelection selection = WallpaperSelection()
      ..selectOnly('e7jvjd')
      ..addListener(() => notifications++)
      ..addAll(<String>['e7jvjd', '7j1mzo']);
    expect(notifications, 1);

    // Already ticked: a rebuild of every tile on the wall for no change.
    selection.addAll(<String>['e7jvjd', '7j1mzo']);
    expect(notifications, 1);
    expect(selection.count, 2);
  });

  test('clear is silent when there was nothing to clear', () {
    int notifications = 0;
    WallpaperSelection()
      ..addListener(() => notifications++)
      ..clear();

    expect(notifications, 0);
  });

  test('the exposed id set cannot be written through', () {
    // The shelf hands these to a batch runner; a caller that mutated them
    // would move the selection without anything rebuilding.
    final WallpaperSelection selection = WallpaperSelection()
      ..selectOnly('e7jvjd');

    expect(() => selection.ids.add('7j1mzo'), throwsUnsupportedError);
  });
}
