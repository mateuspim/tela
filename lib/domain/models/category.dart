import 'package:tela/domain/models/stored_bits.dart';

/// The top-level content buckets Wallhaven files a wallpaper under.
///
/// Not every source has such an axis at all — a booru has none, which is why
/// `Wallpaper.category` is nullable — and the ones that do spell it their own
/// way, so the *encoding* of a category belongs to each adapter.
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

/// The set of categories a search asks for.
///
/// ```dart
/// const CategoryFilter({Category.general}).encodeStored(); // '100'
/// ```
extension type const CategoryFilter(Set<Category> categories) {
  /// The default: everything Wallhaven has.
  static const CategoryFilter all = CategoryFilter({
    Category.general,
    Category.anime,
    Category.people,
  });

  /// Encodes to the 3-bit mask tela stores a saved filter as.
  ///
  /// A storage format, not a request: the `categories` param that happens to
  /// look identical is built in `data/wallhaven/`, and the two are free to
  /// diverge — this one may not, because rows already on disk are written in
  /// it.
  String encodeStored() => encodeStoredBits(Category.values, categories);

  /// Reads back a mask [encodeStored] wrote, or null if [bits] is not one.
  static CategoryFilter? tryParseStored(String bits) {
    final Set<Category>? selected = decodeStoredBits(bits, Category.values);
    return selected == null ? null : CategoryFilter(selected);
  }
}
