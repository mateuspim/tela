import 'package:flutter/services.dart';
import 'package:tela/domain/models/download_deletion.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/download_location.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';
import 'package:tela/domain/models/stored_image.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/image_store.dart';

/// Signature of tela's native image-storage method.
///
/// Arguments are `Map<String, Object?>`, not `Map<String, String>`: the bulk
/// delete sends a list of {tier, location} maps, which the method channel
/// carries but a string-only map cannot type.
typedef InvokeImageStoreMethod =
    Future<Object?> Function(String method, Map<String, Object?> arguments);

/// [ImageStore] backed by tela's Android Storage Access Framework adapter.
///
/// Native code owns all filesystem and MediaStore calls, including the NSFW
/// guard. Dart sends purity as data so the invariant stays at the I/O boundary.
class MethodChannelImageStore implements ImageStore {
  /// Creates an adapter whose native invocation can be replaced in tests.
  MethodChannelImageStore({InvokeImageStoreMethod? invokeMethod})
    : _invokeMethod = invokeMethod ?? _invokeNativeMethod;

  final InvokeImageStoreMethod _invokeMethod;

  static const MethodChannel _channel = MethodChannel('cc.pym.tela/images');

  @override
  Future<StoredImage> store({
    required SourceId source,
    required String id,
    required String imageUrl,
    required Purity purity,
    required StorageTier tier,
    TagFolder? tag,
  }) async {
    try {
      final Object? raw = await _invokeMethod(
        'storeImage',
        <String, Object?>{
          'source': source.value,
          'id': id,
          'imageUrl': imageUrl,
          'purity': purity.name,
          'tier': tier.name,
          ..._tagArgument(tag),
        },
      );
      return _storedImageFrom(raw, tier);
    } on PlatformException catch (error) {
      throw ImageStoreFailure(_problemFor(error.code));
    }
  }

  @override
  Future<StoredImage> copyStoredImage({
    required SourceId source,
    required String id,
    required Uri from,
    required Purity purity,
    required StorageTier tier,
    TagFolder? tag,
  }) async {
    try {
      final Object? raw = await _invokeMethod(
        'copyStoredImage',
        <String, Object?>{
          'source': source.value,
          'id': id,
          'from': from.toString(),
          'purity': purity.name,
          'tier': tier.name,
          ..._tagArgument(tag),
        },
      );
      return _storedImageFrom(raw, tier);
    } on PlatformException catch (error) {
      throw ImageStoreFailure(_problemFor(error.code));
    }
  }

  @override
  Future<StoredImage> retagStoredImage({
    required StorageTier tier,
    required Uri location,
    required TagFolder? tag,
  }) async {
    try {
      final Object? raw = await _invokeMethod(
        'retagStoredImage',
        <String, Object?>{
          'tier': tier.name,
          'location': location.toString(),
          ..._tagArgument(tag),
        },
      );
      return _storedImageFrom(raw, tier);
    } on PlatformException catch (error) {
      throw ImageStoreFailure(_problemFor(error.code));
    }
  }

  @override
  Future<List<PrivateImage>> privateImages() async {
    try {
      final Object? raw = await _invokeMethod(
        'listPrivateImages',
        const <String, String>{},
      );
      return _privateImagesFrom(raw);
    } on PlatformException catch (error) {
      throw ImageStoreFailure(_problemFor(error.code));
    }
  }

  @override
  Future<DownloadDeletion> deleteDownload({
    required StorageTier tier,
    required Uri location,
  }) async {
    try {
      final Object? raw = await _invokeMethod(
        'deleteDownload',
        <String, String>{
          'tier': tier.name,
          'location': location.toString(),
        },
      );
      // One item in, so a non-empty result means it went; an empty one is the
      // user declining the gallery prompt, never a failure (that throws below).
      return _deletedLocationsFrom(raw).isNotEmpty
          ? DownloadDeletion.deleted
          : DownloadDeletion.declined;
    } on PlatformException catch (error) {
      throw ImageStoreFailure(_problemFor(error.code));
    }
  }

  @override
  Future<Set<Uri>> deleteDownloads(
    List<({StorageTier tier, Uri location})> targets,
  ) async {
    if (targets.isEmpty) return const <Uri>{};
    try {
      final Object? raw = await _invokeMethod(
        'deleteDownloads',
        <String, Object?>{
          'items': <Map<String, String>>[
            for (final ({StorageTier tier, Uri location}) target in targets)
              <String, String>{
                'tier': target.tier.name,
                'location': target.location.toString(),
              },
          ],
        },
      );
      return _deletedLocationsFrom(raw);
    } on PlatformException catch (error) {
      throw ImageStoreFailure(_problemFor(error.code));
    }
  }

  @override
  Future<bool> galleryDeleteConfirmedBySystem() async {
    try {
      final Object? raw = await _invokeMethod(
        'galleryDeleteConfirmedBySystem',
        const <String, String>{},
      );
      return raw is Map<Object?, Object?> && raw['confirmed'] == true;
    } on PlatformException {
      // The safe guess keeps tela's own confirmation on: worst case is one
      // extra tap, never a silent delete.
      return false;
    }
  }

  /// The locations the native side reports it deleted, as a set.
  ///
  /// Both the single and the bulk delete answer the same shape — a `deleted`
  /// list — so a single delete is just the one-or-zero-item case of the bulk
  /// one. A refused delete (`success:false`) throws instead.
  Set<Uri> _deletedLocationsFrom(Object? raw) {
    if (raw is Map<Object?, Object?> && raw['success'] == true) {
      final Object? deleted = raw['deleted'];
      if (deleted is! List<Object?>) return const <Uri>{};
      return <Uri>{
        for (final Object? entry in deleted)
          if (entry is String) Uri.parse(entry),
      };
    }
    final Object? code = raw is Map<Object?, Object?> ? raw['errorCode'] : null;
    throw ImageStoreFailure(_problemFor(code));
  }

  /// Answers false for every way a file can fail to open, and never throws.
  ///
  /// The one caller draws a *tile* with this: a history row whose file is gone
  /// still sets its wallpaper (by re-fetching), so a failure to answer must
  /// cost the badge and not the screen. Unreadable is also the safe guess — the
  /// worst it does is warn about a download that is actually still there.
  @override
  Future<bool> canRead(Uri location) async {
    try {
      final Object? raw = await _invokeMethod('canReadImage', <String, String>{
        'location': location.toString(),
      });
      return raw is Map<Object?, Object?> && raw['readable'] == true;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<List<bool>> canReadAll(List<Uri> locations) async {
    if (locations.isEmpty) return const <bool>[];
    try {
      final Object? raw = await _invokeMethod('canReadImages', <String, Object>{
        'locations': <String>[for (final Uri l in locations) l.toString()],
      });
      return _readableFlags(raw, locations.length);
    } on PlatformException {
      return List<bool>.filled(locations.length, false);
    }
  }

  /// Reads the native answer, padding to [expected] if it is short.
  ///
  /// A truncated or malformed reply reads as "cannot open", never as an
  /// exception and never as a shorter list: the caller pairs these with its
  /// records **by index**, so a list of the wrong length would silently badge
  /// the wrong wallpapers as missing.
  List<bool> _readableFlags(Object? raw, int expected) {
    final List<bool> flags = <bool>[
      if (raw is Map<Object?, Object?> && raw['readable'] is List<Object?>)
        for (final Object? flag in raw['readable']! as List<Object?>)
          flag == true,
    ];
    if (flags.length == expected) return flags;
    return <bool>[
      for (int i = 0; i < expected; i++) i < flags.length && flags[i],
    ];
  }

  @override
  Future<DownloadLocation> downloadLocation() async {
    try {
      final Object? raw = await _invokeMethod(
        'describeDownloadLocation',
        const <String, String>{},
      );
      return _downloadLocationFrom(raw);
    } on PlatformException {
      // The row can still offer "choose a folder"; it just cannot yet say a
      // card is present. False is the safe guess — it hides an option rather
      // than inventing one.
      return const DownloadLocation(folder: null, sdCardAvailable: false);
    }
  }

  @override
  Future<DownloadFolder?> chooseDownloadFolder(StorageVolumeKind kind) async {
    try {
      final Object? raw = await _invokeMethod(
        'chooseDownloadFolder',
        <String, String>{'kind': kind.name},
      );
      if (raw is! Map<Object?, Object?> || raw['success'] != true) return null;
      return _downloadFolderFrom(raw['folder']);
    } on PlatformException {
      return null;
    }
  }

  DownloadLocation _downloadLocationFrom(Object? raw) {
    if (raw is! Map<Object?, Object?> || raw['success'] != true) {
      return const DownloadLocation(folder: null, sdCardAvailable: false);
    }
    return DownloadLocation(
      folder: _downloadFolderFrom(raw['folder']),
      sdCardAvailable: raw['sdCardAvailable'] == true,
    );
  }

  DownloadFolder? _downloadFolderFrom(Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    final Object? label = raw['volumeLabel'];
    final Object? path = raw['relativePath'];
    final Object? removable = raw['isRemovable'];
    final Object? available = raw['isAvailable'];
    if (label is! String || path is! String) return null;
    if (removable is! bool || available is! bool) return null;
    return DownloadFolder(
      volumeLabel: label,
      relativePath: path,
      isRemovable: removable,
      isAvailable: available,
      freeBytes: _positiveOrNull(raw['freeBytes']),
    );
  }

  static Future<Object?> _invokeNativeMethod(
    String method,
    Map<String, Object?> arguments,
  ) {
    return _channel.invokeMethod<Object?>(method, arguments);
  }

  /// Maps the native listing, skipping any entry the platform mangled.
  ///
  /// A single unreadable row must not empty the whole library — the user would
  /// read that as "my files are gone", which is far worse than one lost tile.
  List<PrivateImage> _privateImagesFrom(Object? raw) {
    if (raw is! Map<Object?, Object?> || raw['success'] != true) {
      final Object? code = raw is Map<Object?, Object?>
          ? raw['errorCode']
          : null;
      throw ImageStoreFailure(_problemFor(code));
    }
    final Object? images = raw['images'];
    if (images is! List<Object?>) return const <PrivateImage>[];
    return images.map(_privateImageFrom).whereType<PrivateImage>().toList();
  }

  PrivateImage? _privateImageFrom(Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    final Object? ref = raw['ref'];
    final Object? location = raw['location'];
    final Object? savedAt = raw['savedAt'];
    final Object? sizeBytes = raw['sizeBytes'];
    if (ref is! String || location is! String) return null;
    if (savedAt is! int || sizeBytes is! int) return null;
    // Skipped rather than thrown on: the private directory holds names tela
    // wrote, but nothing stops a file arriving there by other means, and one
    // such file must cost its own tile and not the whole listing.
    final WallpaperRef? parsed = WallpaperRef.tryParse(ref);
    if (parsed == null) return null;
    return PrivateImage(
      ref: parsed,
      location: Uri.parse(location),
      savedAt: DateTime.fromMillisecondsSinceEpoch(savedAt),
      sizeBytes: sizeBytes,
      // Off the directory holding the file. This tier keeps no rows, so the
      // layout on disk is the only record of what an image is filed under.
      tag: _tagFrom(raw['tag']),
      width: _positiveOrNull(raw['width']),
      height: _positiveOrNull(raw['height']),
    );
  }

  /// A measurement the native side either read or could not, as int-or-null.
  ///
  /// Two things arrive this way and both mean it the same: a pixel dimension
  /// from the bounds decode, which comes back -1 for a corrupt file (or absent
  /// on an older payload), and free space, which is simply missing when
  /// `fstatvfs` failed. In each case the row still draws, just without that
  /// fact.
  int? _positiveOrNull(Object? value) =>
      value is int && value > 0 ? value : null;

  StoredImage _storedImageFrom(Object? raw, StorageTier tier) {
    if (raw is Map<Object?, Object?> && raw['success'] == true) {
      final Object? location = raw['location'];
      if (location is String) {
        return StoredImage(
          location: Uri.parse(location),
          tier: tier,
          // The tag the native side reports having used, not the one that was
          // asked for. An absent key is an untagged write, which is how every
          // response read before tags existed.
          tag: _tagFrom(raw['tag']),
        );
      }
    }
    final Object? code = raw is Map<Object?, Object?> ? raw['errorCode'] : null;
    throw ImageStoreFailure(_problemFor(code));
  }

  /// The `tag` argument, or nothing at all when the write is untagged.
  ///
  /// Omitted rather than sent as null so an untagged call puts exactly the
  /// payload on the wire that it did before tags existed. The native side reads
  /// an absent key and an explicit null identically, so this costs nothing
  /// there and keeps "untagged behaves as it always did" true of the crossing
  /// itself, not just of its effect.
  static Map<String, Object?> _tagArgument(TagFolder? tag) => tag == null
      ? const <String, Object?>{}
      : <String, Object?>{'tag': tag.name};

  /// Reads a tag off a native response, refusing one that is not a legal
  /// folder name rather than constructing an impossible [TagFolder].
  static TagFolder? _tagFrom(Object? raw) {
    if (raw is! String || !TagFolder.isLegal(raw)) return null;
    return TagFolder(raw);
  }

  ImageStoreProblem _problemFor(Object? code) {
    return switch (code) {
      'downloadFailed' => ImageStoreProblem.source,
      'unavailable' => ImageStoreProblem.unavailable,
      'notConfigured' => ImageStoreProblem.notConfigured,
      'folderUnavailable' => ImageStoreProblem.folderUnavailable,
      'restricted' => ImageStoreProblem.restricted,
      _ => ImageStoreProblem.unknown,
    };
  }
}
