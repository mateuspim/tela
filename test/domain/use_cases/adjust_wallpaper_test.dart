import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_adjust_failure.dart';
import 'package:tela/domain/use_cases/adjust_wallpaper.dart';

import '../../fakes/fake_system_wallpaper_editor.dart';

void main() {
  test('opens the editor on the full image, named from its URL', () async {
    final FakeSystemWallpaperEditor editor = FakeSystemWallpaperEditor();
    final AdjustWallpaper adjust = AdjustWallpaper(editor: editor);

    await adjust(_wallpaper());

    expect(editor.opened, hasLength(1));
    expect(
      editor.opened.single.source,
      Uri.parse('https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.png'),
    );
    // The extension is what makes FileProvider type it image/*, which is the
    // platform's own precondition for the crop-and-set intent.
    expect(editor.opened.single.fileName, 'wallhaven-e7jvjd.png');
  });

  test('a sketchy wallpaper is allowed through', () async {
    final FakeSystemWallpaperEditor editor = FakeSystemWallpaperEditor();
    final AdjustWallpaper adjust = AdjustWallpaper(editor: editor);

    await adjust(_wallpaper(purity: Purity.sketchy));

    expect(editor.opened, hasLength(1));
  });

  test(
    'an explicit wallpaper is refused and never reaches the port',
    () async {
      final FakeSystemWallpaperEditor editor = FakeSystemWallpaperEditor();
      final AdjustWallpaper adjust = AdjustWallpaper(editor: editor);

      await expectLater(
        () => adjust(_wallpaper(purity: Purity.nsfw)),
        throwsA(isA<ArgumentError>()),
      );
      // The point of the guard: the pixels never left, so nothing to clean up.
      expect(editor.opened, isEmpty);
    },
  );

  test('the refusal names the offending wallpaper', () async {
    final AdjustWallpaper adjust = AdjustWallpaper(
      editor: FakeSystemWallpaperEditor(),
    );

    await expectLater(
      () => adjust(_wallpaper(purity: Purity.nsfw)),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError error) => error.message,
          'message',
          contains('e7jvjd'),
        ),
      ),
    );
  });

  test('an operational failure reaches the caller unchanged', () async {
    final FakeSystemWallpaperEditor editor = FakeSystemWallpaperEditor(
      failure: const WallpaperAdjustFailure(WallpaperAdjustProblem.unavailable),
    );
    final AdjustWallpaper adjust = AdjustWallpaper(editor: editor);

    await expectLater(
      () => adjust(_wallpaper()),
      throwsA(
        isA<WallpaperAdjustFailure>().having(
          (WallpaperAdjustFailure failure) => failure.problem,
          'problem',
          WallpaperAdjustProblem.unavailable,
        ),
      ),
    );
  });
}

Wallpaper _wallpaper({Purity purity = Purity.sfw}) => Wallpaper(
  id: 'e7jvjd',
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
