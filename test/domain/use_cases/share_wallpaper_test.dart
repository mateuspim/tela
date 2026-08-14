import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/clipboard_confirmation.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/use_cases/share_wallpaper.dart';

import '../../fakes/fake_wallpaper_sharer.dart';

void main() {
  test('link shares the public Wallhaven page', () async {
    final FakeWallpaperSharer sharer = FakeWallpaperSharer();
    final ShareWallpaper share = ShareWallpaper(sharer: sharer);

    await share.link(_wallpaper());

    expect(sharer.sharedLinks, <Uri>[
      Uri.parse('https://wallhaven.cc/w/e7jvjd'),
    ]);
    expect(sharer.sharedImages, isEmpty);
  });

  test(
    'image shares the full URL and a file name with the real extension',
    () async {
      final FakeWallpaperSharer sharer = FakeWallpaperSharer();
      final ShareWallpaper share = ShareWallpaper(sharer: sharer);

      await share.image(_wallpaper());

      expect(sharer.sharedImages, hasLength(1));
      expect(
        sharer.sharedImages.single.source,
        Uri.parse('https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.png'),
      );
      // Taken from the URL, so a PNG keeps .png rather than a guessed .jpg.
      expect(sharer.sharedImages.single.fileName, 'wallhaven-e7jvjd.png');
    },
  );

  test(
    'image is refused for an explicit wallpaper and never reaches the port',
    () async {
      final FakeWallpaperSharer sharer = FakeWallpaperSharer();
      final ShareWallpaper share = ShareWallpaper(sharer: sharer);

      expect(
        () => share.image(_wallpaper(purity: Purity.nsfw)),
        throwsA(isA<ArgumentError>()),
      );
      expect(sharer.sharedImages, isEmpty);
    },
  );

  test('clipboard copies the same file the image share would send', () async {
    final FakeWallpaperSharer sharer = FakeWallpaperSharer();
    final ShareWallpaper share = ShareWallpaper(sharer: sharer);

    final ClipboardConfirmation confirmation = await share.clipboard(
      _wallpaper(),
    );

    expect(sharer.copiedImages, hasLength(1));
    expect(
      sharer.copiedImages.single.source,
      Uri.parse('https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.png'),
    );
    expect(sharer.copiedImages.single.fileName, 'wallhaven-e7jvjd.png');
    // Passed through from the port: the platform decides who confirmed it.
    expect(confirmation, ClipboardConfirmation.tela);
  });

  test('clipboard reports back what the port says about the notice', () async {
    final FakeWallpaperSharer sharer = FakeWallpaperSharer(
      confirmation: ClipboardConfirmation.system,
    );
    final ShareWallpaper share = ShareWallpaper(sharer: sharer);

    expect(await share.clipboard(_wallpaper()), ClipboardConfirmation.system);
  });

  test('an explicit wallpaper is copied, and marked sensitive', () async {
    // The copy is allowed at every purity; the flag is what tela still controls
    // once the bytes are on the clipboard, and it keeps the picture out of the
    // system's own preview. A copy that travelled unmarked would put an
    // explicit thumbnail on screen for anyone standing nearby.
    final FakeWallpaperSharer sharer = FakeWallpaperSharer();
    final ShareWallpaper share = ShareWallpaper(sharer: sharer);

    await share.clipboard(_wallpaper(purity: Purity.nsfw));

    expect(sharer.copiedImages.single.sensitive, isTrue);
  });

  test('a safe wallpaper is copied unmarked', () async {
    final FakeWallpaperSharer sharer = FakeWallpaperSharer();
    final ShareWallpaper share = ShareWallpaper(sharer: sharer);

    await share.clipboard(_wallpaper());

    expect(sharer.copiedImages.single.sensitive, isFalse);
  });

  test(
    'link is allowed for an explicit wallpaper — the page is public',
    () async {
      final FakeWallpaperSharer sharer = FakeWallpaperSharer();
      final ShareWallpaper share = ShareWallpaper(sharer: sharer);

      await share.link(_wallpaper(purity: Purity.nsfw));

      expect(sharer.sharedLinks, hasLength(1));
    },
  );
}

Wallpaper _wallpaper({Purity purity = Purity.sfw}) => Wallpaper(
  id: 'e7jvjd',
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/e7jvjd'),
  fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.png',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/e7jvjd.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg',
  resolution: const Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: purity,
  category: Category.general,
  colors: const <String>[],
);
