import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';

/// How the enum and list fields of a stored wallpaper are read back.
///
/// Shared by every table that keeps a whole wallpaper (favorites, downloads):
/// the fail-safe rules below are the load-bearing part of the mapping, and a
/// second copy of them is a second chance to get one of them wrong.

/// Reads a stored source, treating an empty cell as Wallhaven.
///
/// Empty is the one value that has a meaning: a row written before schema v6
/// predates the column entirely, and Wallhaven was the only source there was.
/// Anything else is taken at face value rather than validated — a source id
/// this build does not know is a wallpaper from a version that did, and losing
/// the whole listing over it would be a worse answer than an unrenderable tile.
SourceId storedSource(String stored) {
  if (stored.isEmpty) return SourceId.wallhaven;
  return SourceId(stored);
}

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

/// Reads a stored category, answering null for a source that has none.
///
/// An empty cell is a wallpaper from a source with no category axis, and an
/// unreadable one is treated the same way: a wrong category is a claim tela
/// would be making on the source's behalf, where no category is merely silent.
Category? storedCategory(String stored) {
  if (stored.isEmpty) return null;
  return Category.values
      .where((Category category) => category.name == stored)
      .firstOrNull;
}

/// Writes a category, or the empty cell that means the source has none.
String storableCategory(Category? category) => category?.name ?? '';

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

/// Reads a stored tag, answering null for anything that is not a legal folder.
///
/// Null covers three cases that are all genuinely "untagged": a row written
/// before schema v8, a download that was never tagged, and a stored name that
/// this build would no longer accept as a directory. The last is the reason
/// this is not a bare `TagFolder(stored)` — the column holds whatever some
/// version once wrote, and a name that cannot be a folder must not be handed
/// back as one to a caller that will go looking for it on disk.
TagFolder? storedTag(String? stored) {
  if (stored == null) return null;
  return TagFolder.isLegal(stored) ? TagFolder(stored) : null;
}
