import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/build_edition.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';
import 'package:tela/domain/use_cases/find_broken_images.dart';
import 'package:tela/domain/use_cases/repair_broken_images.dart';

/// Finds the damaged images across every tier tela stores in.
final Provider<FindBrokenImages> findBrokenImagesProvider =
    Provider<FindBrokenImages>(
      (Ref ref) => FindBrokenImages(
        imageStore: ref.watch(imageStoreProvider),
        history: ref.watch(downloadHistoryProvider),
      ),
    );

/// Re-downloads the damaged images, or removes the ones it cannot.
///
/// Each one is looked up through **the source that issued it**, not the
/// active one — see `wallpaperSourceForProvider` — and stored through the same
/// `DownloadWallpaper` a tap on Download uses, so the NSFW routing and the
/// history row are the ones every other download gets.
final Provider<RepairBrokenImages>
repairBrokenImagesProvider = Provider<RepairBrokenImages>(
  (Ref ref) => RepairBrokenImages(
    fetch: (WallpaperRef wallpaper) => _fetch(ref, wallpaper),
    store: (Wallpaper wallpaper, {required StorageTier tier, TagFolder? tag}) =>
        _store(ref, wallpaper, tier, tag),
    imageStore: ref.watch(imageStoreProvider),
    history: ref.watch(downloadHistoryProvider),
  ),
);

/// The wallpaper [wallpaper] names, through the source that issued it.
///
/// A file from a source this build no longer has is [NotFoundFailure] here
/// rather than `wallpaperSourceForProvider`'s `ArgumentError`: to the repair it
/// is simply a wallpaper that cannot be had again, and an `Error` is not
/// something a use case may catch.
Future<Wallpaper> _fetch(Ref ref, WallpaperRef wallpaper) async {
  final WallpaperSource? source = ref
      .read(wallpaperSourcesProvider)
      .where((WallpaperSource s) => s.id == wallpaper.source)
      .firstOrNull;
  if (source == null) throw NotFoundFailure(wallpaper.id);
  final WallpaperDetails details = await source.wallpaperDetails(wallpaper.id);
  return details.wallpaper;
}

/// Stores [wallpaper] the way a Download tap would.
///
/// An explicit wallpaper in a build that may not keep one is refused as
/// [ImageStoreProblem.restricted] before `DownloadWallpaper` can raise its
/// `UnsupportedError`, for the same reason [_fetch] avoids an `Error`.
Future<StoredImage> _store(
  Ref ref,
  Wallpaper wallpaper,
  StorageTier tier,
  TagFolder? tag,
) {
  if (wallpaper.isNsfw && !buildEdition.allowsExplicitContent) {
    throw const ImageStoreFailure(ImageStoreProblem.restricted);
  }
  return ref.read(downloadWallpaperProvider)(wallpaper, tier: tier, tag: tag);
}
