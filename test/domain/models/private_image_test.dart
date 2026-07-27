import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

void main() {
  test('aspectRatio divides known pixel dimensions', () {
    final PrivateImage image = _image(width: 1080, height: 2400);

    expect(image.aspectRatio, closeTo(1080 / 2400, 1e-9));
  });

  test('aspectRatio is null when a dimension is unknown', () {
    // A corrupt file the native bounds decode could not read: the gallery must
    // fall back to a square rather than divide by an unknown dimension.
    expect(_image(width: null, height: null).aspectRatio, isNull);
    expect(_image(width: 1080, height: null).aspectRatio, isNull);
  });

  test('aspectRatio is null for a non-positive dimension', () {
    expect(_image(width: 0, height: 2400).aspectRatio, isNull);
    expect(_image(width: -1, height: -1).aspectRatio, isNull);
  });

  test('toString names the image without naming where it lives', () {
    // CLAUDE.md forbids logging a private path; printing one must not leak it.
    final String text = _image(width: 1, height: 1).toString();

    expect(text, contains('e7jvjd'));
    expect(text, isNot(contains('wallpapers')));
    expect(text, isNot(contains('.jpg')));
  });
}

PrivateImage _image({required int? width, required int? height}) =>
    PrivateImage(
      ref: const WallpaperRef(SourceId.wallhaven, 'e7jvjd'),
      location: Uri.file(
        '/data/user/0/cc.pym.tela/files/wallpapers/w-e7jvjd.jpg',
      ),
      savedAt: DateTime.utc(2026, 7, 14),
      sizeBytes: 2048,
      width: width,
      height: height,
    );
