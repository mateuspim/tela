import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/tag_folder.dart';

/// The tag the user files a download under, which is a folder on disk.
///
/// Two doors, and the difference between them is the point: [TagFolder.new]
/// throws for a name that could not be a directory, because its callers hold a
/// name they already believe in; [TagFolder.sanitize] repairs and answers null,
/// because its callers hold a source's own tag or a half-typed line.
void main() {
  group('TagFolder', () {
    test('accepts the names a user would reasonably type', () {
      for (final String name in <String>[
        'anime',
        'Nature',
        'sci fi',
        'hatsune_miku',
        '4k-walls',
        '2026',
      ]) {
        expect(TagFolder(name).name, name);
      }
    });

    test('names the offending value and the expected shape when it throws', () {
      expect(
        () => TagFolder('../secrets'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            allOf(contains('../secrets'), contains('letters, digits')),
          ),
        ),
      );
    });

    /// Every one of these is refused by the same rule — no `.`, no separator —
    /// rather than by a case each, which is why the dot is excluded outright.
    test('refuses anything that could traverse or hide', () {
      for (final String name in <String>[
        '..',
        '.',
        '../secrets',
        'a/b',
        r'a\b',
        '.nomedia',
        '.hidden',
      ]) {
        expect(TagFolder.isLegal(name), isFalse, reason: name);
      }
    });

    test('refuses an empty or over-long name', () {
      expect(TagFolder.isLegal(''), isFalse);
      expect(TagFolder.isLegal('x' * 33), isFalse);
      expect(TagFolder.isLegal('x' * 32), isTrue);
    });

    /// A space is legal inside a tag, so a flat character class would accept
    /// `' anime'` — a folder indistinguishable from `anime` in every list the
    /// user reads, and a different directory on disk.
    test('refuses a leading or trailing space, and keeps an inner one', () {
      expect(TagFolder.isLegal(' anime'), isFalse);
      expect(TagFolder.isLegal('anime '), isFalse);
      expect(TagFolder.isLegal(' '), isFalse);
      expect(TagFolder.isLegal('sci fi'), isTrue);
    });

    test('is equal by name, and case-sensitively', () {
      expect(TagFolder('anime'), TagFolder('anime'));
      expect(TagFolder('anime'), isNot(TagFolder('Anime')));
    });
  });

  group('TagFolder.sanitize', () {
    test('keeps a source tag that is already a legal folder name', () {
      expect(TagFolder.sanitize('hatsune_miku')?.name, 'hatsune_miku');
      expect(TagFolder.sanitize('long hair')?.name, 'long hair');
    });

    test('trims and collapses whitespace', () {
      expect(TagFolder.sanitize('  anime  ')?.name, 'anime');
      expect(TagFolder.sanitize('sci    fi')?.name, 'sci fi');
    });

    /// Dropped, not substituted. A repair that invents characters — `sci-fi`
    /// out of `sci/fi` — makes a second folder that looks like one the user
    /// already has, and candidates are matched against existing folders.
    test('drops illegal characters rather than replacing them', () {
      expect(TagFolder.sanitize('sci/fi')?.name, 'sci fi');
      expect(TagFolder.sanitize('café')?.name, 'caf');
      expect(TagFolder.sanitize('anime★')?.name, 'anime');
    });

    test('caps at the maximum length without leaving a trailing space', () {
      expect(TagFolder.sanitize('x' * 40)?.name, 'x' * 32);
      expect(TagFolder.sanitize('${'x' * 32} tail')?.name, 'x' * 32);
      expect(TagFolder.sanitize('${'x' * 31} tail')?.name, 'x' * 31);
    });

    /// A source tag that reduces to nothing is an ordinary thing to find in a
    /// list of candidates, not an error to raise.
    test('answers null when nothing legal survives', () {
      expect(TagFolder.sanitize('>_<'.replaceAll('_', '')), isNull);
      expect(TagFolder.sanitize('...'), isNull);
      expect(TagFolder.sanitize('   '), isNull);
      expect(TagFolder.sanitize(''), isNull);
    });

    test('what it produces is always legal', () {
      for (final String raw in <String>[
        '..',
        './anime',
        ' anime ',
        'a/b/c',
        'x' * 99,
      ]) {
        final TagFolder? tag = TagFolder.sanitize(raw);
        if (tag != null) {
          expect(TagFolder.isLegal(tag.name), isTrue, reason: raw);
        }
      }
    });
  });
}
