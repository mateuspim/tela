import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/share_option.dart';

void main() {
  test('safe and sketchy wallpapers may share the link or the image', () {
    for (final Purity purity in <Purity>[Purity.sfw, Purity.sketchy]) {
      expect(
        shareOptionsFor(purity),
        <ShareOption>[ShareOption.link, ShareOption.image],
        reason: '$purity is not explicit, so the image file may leave',
      );
    }
  });

  test('an explicit wallpaper may share the link but never the image', () {
    // The NSFW invariant: an explicit bitmap never leaves the device as a file.
    expect(shareOptionsFor(Purity.nsfw), <ShareOption>[ShareOption.link]);
    expect(shareOptionsFor(Purity.nsfw), isNot(contains(ShareOption.image)));
  });
}
