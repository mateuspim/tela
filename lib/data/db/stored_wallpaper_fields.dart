import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';

/// How the enum and list fields of a stored wallpaper are read back.
///
/// Shared by every table that keeps a whole wallpaper (favorites, downloads):
/// the fail-safe rules below are the load-bearing part of the mapping, and a
/// second copy of them is a second chance to get one of them wrong.

/// Reads a stored purity, treating an unrecognised one as [Purity.nsfw].
///
/// Deliberately fails *closed*, unlike every other fallback in this codebase.
/// Purity is what routes a download and what gates MediaStore indexing, so a
/// corrupt row read as `sfw` is the one mistake that could index an explicit
/// image. Read as `nsfw` it is merely over-protected, which is survivable.
Purity storedPurity(String stored) {
  return Purity.values
          .where((Purity purity) => purity.name == stored)
          .firstOrNull ??
      Purity.nsfw;
}

/// Reads a stored category, falling back to [Category.general].
Category storedCategory(String stored) {
  return Category.values
          .where((Category category) => category.name == stored)
          .firstOrNull ??
      Category.general;
}

/// Reads a stored storage tier, falling back to [StorageTier.sharedGallery].
///
/// Unlike [storedPurity] this one may fail open, because it routes nothing: the
/// file it names is already written, and the tier is only how the download is
/// labelled after the fact.
StorageTier storedTier(String stored) {
  return StorageTier.values
          .where((StorageTier tier) => tier.name == stored)
          .firstOrNull ??
      StorageTier.sharedGallery;
}

/// Splits the comma-joined colours, mapping an empty cell to no colours rather
/// than to a list holding one empty string.
List<String> storedColors(String stored) {
  if (stored.isEmpty) return const <String>[];
  return stored.split(',');
}

/// Joins colours for storage, in Wallhaven's order.
String joinedColors(List<String> colors) => colors.join(',');
