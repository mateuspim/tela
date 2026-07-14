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
    return switch (raw) {
      'general' => Category.general,
      'anime' => Category.anime,
      'people' => Category.people,
      _ => throw ArgumentError(
        'category must be general|anime|people, got "$raw"',
      ),
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
}
