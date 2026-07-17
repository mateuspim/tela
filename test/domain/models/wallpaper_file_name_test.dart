import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_file_name.dart';

void main() {
  test('takes the name from the URL, keeping the real extension', () {
    // A guessed .jpg would be wrong here, and the receiving app believes it.
    expect(wallpaperFileName(_wallpaper()), 'wallhaven-e7jvjd.png');
  });

  test('a jpg keeps .jpg', () {
    expect(
      wallpaperFileName(
        _wallpaper(url: 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg'),
      ),
      'wallhaven-e7jvjd.jpg',
    );
  });

  test('falls back to the id when the URL has no last segment', () {
    expect(
      wallpaperFileName(_wallpaper(url: 'https://w.wallhaven.cc/')),
      'wallhaven-e7jvjd',
    );
  });

  test('falls back to the id when the URL has no path at all', () {
    expect(
      wallpaperFileName(_wallpaper(url: 'https://w.wallhaven.cc')),
      'wallhaven-e7jvjd',
    );
  });
}

Wallpaper _wallpaper({
  String url = 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.png',
}) => Wallpaper(
  id: 'e7jvjd',
  fullImageUrl: url,
  thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/e7jvjd.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg',
  resolution: const Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);
