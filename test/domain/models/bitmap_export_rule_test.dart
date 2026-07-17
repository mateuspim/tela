import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/bitmap_export_rule.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/share_option.dart';

void main() {
  test('safe and sketchy wallpapers may have their pixels leave the app', () {
    expect(mayExportBitmap(Purity.sfw), isTrue);
    // Sketchy is not explicit anywhere else either — StorageSettings.choicesFor
    // and Wallpaper.isNsfw both draw the line at nsfw alone.
    expect(mayExportBitmap(Purity.sketchy), isTrue);
  });

  test('an explicit wallpaper may not', () {
    expect(mayExportBitmap(Purity.nsfw), isFalse);
  });

  test('every purity is decided, so a new one cannot slip through', () {
    // Not a tautology: it fails the day Purity gains a value and this rule is
    // not asked about it, which is exactly when a bitmap would leak by default.
    for (final Purity purity in Purity.values) {
      expect(mayExportBitmap(purity), purity != Purity.nsfw, reason: '$purity');
    }
  });

  test('the share menu asks this rule rather than purity of its own', () {
    // The two must not be able to drift: if shareOptionsFor stops agreeing with
    // mayExportBitmap, one of the two ways bytes leave the app has its own idea
    // of the NSFW rule, and that is the bug this pins.
    for (final Purity purity in Purity.values) {
      expect(
        shareOptionsFor(purity).contains(ShareOption.image),
        mayExportBitmap(purity),
        reason: '$purity',
      );
    }
  });
}
