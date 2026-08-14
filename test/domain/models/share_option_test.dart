import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/share_option.dart';

void main() {
  test('safe and sketchy wallpapers may share the link or the image', () {
    for (final Purity purity in <Purity>[Purity.sfw, Purity.sketchy]) {
      expect(
        shareOptionsFor(purity),
        <ShareOption>[
          ShareOption.link,
          ShareOption.image,
          ShareOption.clipboard,
        ],
        reason: '$purity is not explicit, so the image file may leave',
      );
    }
  });

  test('an explicit wallpaper may share the link but never the image', () {
    // The NSFW invariant that still holds: an explicit bitmap never leaves as a
    // *file* a receiving app then keeps.
    expect(shareOptionsFor(Purity.nsfw), isNot(contains(ShareOption.image)));
  });

  test('an explicit wallpaper may still be copied', () {
    // Reversed 2026-08-13 by the owner's decision, after shipping withheld:
    // refusing the copy made the app's fastest route into another app useless
    // on the images it was most wanted for. What the copy gives up in exchange
    // is written down at `shareOptionsFor`; what it does *not* touch is the
    // storage side, which is what CLAUDE.md's hard rules are about.
    expect(shareOptionsFor(Purity.nsfw), <ShareOption>[
      ShareOption.link,
      ShareOption.clipboard,
    ]);
  });
}
