import 'package:tela/domain/models/api_bits.dart';

/// Wallhaven's top-level content buckets.
///
/// Same two-dialect problem as `Purity`: a wallpaper's JSON says `"general"`,
/// the `/search` param wants a 3-bit mask in the fixed order
/// `general anime people`.
///
/// ```dart
/// Category.fromApiName('anime'); // Category.anime
/// ```
enum Category {
  /// Everything that isn't anime or people — landscapes, abstract, space.
  general,

  /// Anime and illustrated art.
  anime,

  /// Photography of people.
  people;

  /// Parses the `category` field of a wallpaper JSON object.
  static Category fromApiName(String raw) {
    final Category? category = tryFromApiName(raw);
    if (category == null) {
      throw ArgumentError('category must be general|anime|people, got "$raw"');
    }
    return category;
  }

  /// Parses a category name, answering null instead of throwing.
  ///
  /// For the account's category list, where a bucket tela does not know yet
  /// should cost that bucket and not the whole sync.
  static Category? tryFromApiName(String raw) {
    return switch (raw) {
      'general' => Category.general,
      'anime' => Category.anime,
      'people' => Category.people,
      _ => null,
    };
  }
}

/// The set of categories a search asks for, as Wallhaven's 3-bit mask.
///
/// ```dart
/// const CategoryFilter({Category.general}).toApiBits(); // '100'
/// ```
extension type const CategoryFilter(Set<Category> categories) {
  /// The default: everything Wallhaven has.
  static const CategoryFilter all = CategoryFilter({
    Category.general,
    Category.anime,
    Category.people,
  });

  /// Encodes to the 3-bit `categories` query param.
  String toApiBits() {
    final String bits = Category.values
        .map((Category c) => categories.contains(c) ? '1' : '0')
        .join();
    if (bits == '000') {
      throw ArgumentError(
        'category filter must select at least one of '
        'general|anime|people, got none',
      );
    }
    return bits;
  }

  /// Reads back a mask [toApiBits] wrote, or null if [bits] is not one.
  static CategoryFilter? tryFromApiBits(String bits) {
    final Set<Category>? selected = decodeApiBits(bits, Category.values);
    return selected == null ? null : CategoryFilter(selected);
  }
}
