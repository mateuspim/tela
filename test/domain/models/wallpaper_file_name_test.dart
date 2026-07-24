import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_file_name.dart';

void main() {
  test('takes the extension from the URL, keeping the real one', () {
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

  test('names the file after the source that issued it', () {
    expect(
      wallpaperFileName(
        _wallpaper(
          id: '406484',
          source: const SourceId('konachan'),
          // A booru names its file after the tags on the image. Lifting that
          // name whole would hand another app a list of what is in the
          // picture — including the explicit ones.
          url:
              'https://konachan.com/image/ab/Konachan.com%20-%20406484'
              '%20black_hair%20nude.jpg',
        ),
      ),
      'konachan-406484.jpg',
    );
  });
}

Wallpaper _wallpaper({
  String url = 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.png',
  String id = 'e7jvjd',
  SourceId source = SourceId.wallhaven,
}) => Wallpaper(
  id: id,
  source: source,
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
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
