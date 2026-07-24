import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

void main() {
  group('SourceId', () {
    test('parses a well-shaped id', () {
      expect(SourceId.parse('konachan'), SourceId.konachan);
      expect(SourceId.parse('wallhaven').value, 'wallhaven');
    });

    test('refuses a shape no adapter could have written', () {
      // Names the offending value and the expected shape, per CLAUDE.md.
      expect(
        () => SourceId.parse('Wallhaven'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'message',
            allOf(contains('lowercase'), contains('Wallhaven')),
          ),
        ),
      );
      expect(() => SourceId.parse(''), throwsArgumentError);
      expect(() => SourceId.parse('kona chan'), throwsArgumentError);
    });

    test('two ids with the same value are the same source', () {
      // The literal spelling is the point: a stored row rebuilds the id from
      // its string and must compare equal to the constant the code uses.
      // ignore: use_named_constants
      expect(const SourceId('wallhaven'), SourceId.wallhaven);
      // Same reason: the rebuilt id must hash like the constant too.
      // ignore: use_named_constants
      expect(const SourceId('wallhaven').hashCode, SourceId.wallhaven.hashCode);
      expect(SourceId.konachan, isNot(SourceId.wallhaven));
    });
  });

  group('WallpaperRef', () {
    test('keys on both halves, which is the whole point', () {
      // The collision the source column exists to prevent: two boorus can
      // issue the same numeric id, and they are not the same wallpaper.
      const WallpaperRef konachan = WallpaperRef(SourceId.konachan, '12345');
      const WallpaperRef yandere = WallpaperRef(SourceId('yandere'), '12345');

      expect(konachan, isNot(yandere));
      expect(konachan.key, isNot(yandere.key));
    });

    test('the flat key is the file-name shape', () {
      expect(
        const WallpaperRef(SourceId.wallhaven, 'e7jvjd').key,
        'wallhaven-e7jvjd',
      );
      expect(
        const WallpaperRef(SourceId.konachan, '406484').key,
        'konachan-406484',
      );
    });

    test('same source and id compare and hash alike', () {
      const WallpaperRef a = WallpaperRef(SourceId.wallhaven, 'e7jvjd');
      // Spelled out rather than SourceId.wallhaven, for the reason above.
      // ignore: use_named_constants
      const WallpaperRef b = WallpaperRef(SourceId('wallhaven'), 'e7jvjd');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), 'wallhaven-e7jvjd');
    });
  });
}
