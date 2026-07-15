import 'package:tela/domain/models/wallpaper_details.dart';

/// Tags the user never wants to see again, stored on this device only.
///
/// A pure-domain port: no package sits behind it, and Wallhaven has no idea
/// this list exists — blocking is local, applied client-side by folding each
/// blocked name into every outgoing query as Wallhaven's `-name` exclude
/// operator.
///
/// Kept by id, not just name: two different tags can share a display name,
/// and the id is what lets the management screen unblock the *one* the user
/// meant, and what a later rename does not silently detach from. But the
/// block only ever *reaches Wallhaven* as [blockedNames] — confirmed live,
/// 2026-07-15: `-id:{n}` is silently ignored (the response is identical to no
/// filter at all), where `-name` genuinely excludes. Wallhaven's exact-id
/// operator only ever supports the *include* side.
abstract interface class TagBlocklistRepository {
  /// Every blocked tag, most recently blocked first.
  Future<List<WallpaperTag>> all();

  /// Every blocked tag's name — the shape a search actually filters on.
  Future<Set<String>> blockedNames();

  /// Blocks [tag], replacing any earlier block of the same id.
  Future<void> block(WallpaperTag tag);

  /// Unblocks the tag with [tagId]. A no-op when it was never blocked.
  Future<void> unblock(int tagId);
}
