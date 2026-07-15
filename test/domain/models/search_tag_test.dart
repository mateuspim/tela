import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/search_tag.dart';

void main() {
  group('SearchTag.token', () {
    test('signs an included tag with +, an excluded tag with -', () {
      expect(const SearchTag('nature').token, '+nature');
      expect(const SearchTag('people', TagSense.exclude).token, '-people');
    });

    test('defaults to include — adding a tag usually means "show it"', () {
      expect(const SearchTag('sunset').sense, TagSense.include);
    });
  });

  group('SearchTag.flipped', () {
    test('swaps the sense and keeps the name', () {
      const SearchTag included = SearchTag('nature');
      expect(included.flipped().sense, TagSense.exclude);
      expect(included.flipped().name, 'nature');
      expect(included.flipped().flipped(), included);
    });
  });

  group('SearchTag equality', () {
    test('name and sense together make the constraint', () {
      // The same word demanded and forbidden is two different filters, and both
      // may sit in one query — so they must not compare equal.
      expect(const SearchTag('nature'), const SearchTag('nature'));
      expect(
        const SearchTag('nature'),
        isNot(const SearchTag('nature', TagSense.exclude)),
      );
      expect(const SearchTag('nature'), isNot(const SearchTag('forest')));
    });

    test('hashes consistently with ==, so it is usable as a set member', () {
      // The set-like comparison SearchQuery does over its tags leans on this.
      expect(
        const SearchTag('nature').hashCode,
        const SearchTag('nature').hashCode,
      );
      expect(
        const SearchTag('nature').hashCode,
        isNot(const SearchTag('nature', TagSense.exclude).hashCode),
      );
    });
  });
}
