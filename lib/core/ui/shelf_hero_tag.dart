/// A Hero tag for one image at [position] on one shelf, scoped so no two live
/// tiles ever collide.
///
/// Two things force the scoping. Across shelves: the same Wallhaven id can sit
/// on Browse, in History, and in the private library at once, and go_router
/// keeps every inactive shell branch mounted, so Browse and Favorites tiles for
/// one id are in the tree together — [shelfIdentity] keeps those apart. Within
/// one shelf: Wallhaven's `random` sort can repeat a wallpaper across pages, so
/// a shelf can render the same id twice — [position] (the item's index in the
/// shelf) keeps those apart too. Tagging by id alone would raise "multiple
/// heroes share the same tag" the instant a flight began.
///
/// The viewer a tile opens passes its own selected index as [position], so the
/// tag matches back to the exact tile — and simply does not fly (rather than
/// flying to the wrong image) if a deduplicated page has since shifted it.
///
/// ```dart
/// Hero(tag: shelfHeroTag(session.identity, item.id, index), child: preview);
/// ```
Object shelfHeroTag(String shelfIdentity, String itemId, int position) {
  return 'shelf-hero $shelfIdentity #$position $itemId';
}
