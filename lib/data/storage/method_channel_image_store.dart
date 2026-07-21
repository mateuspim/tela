import 'package:flutter/services.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/download_location.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';
import 'package:tela/domain/models/stored_image.dart';
import 'package:tela/domain/ports/image_store.dart';

/// Signature of tela's native image-storage method.
typedef InvokeImageStoreMethod =
    Future<Object?> Function(String method, Map<String, String> arguments);

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
    required String id,
    required String imageUrl,
    required Purity purity,
    required StorageTier tier,
  }) async {
    try {
      final Object? raw = await _invokeMethod(
        'storeImage',
        <String, String>{
          'id': id,
          'imageUrl': imageUrl,
          'purity': purity.name,
          'tier': tier.name,
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
  Future<void> deletePrivateImage(String id) async {
    try {
      final Object? raw = await _invokeMethod(
        'deletePrivateImage',
        <String, String>{
          'id': id,
        },
      );
      if (raw is Map<Object?, Object?> && raw['success'] == true) return;
      final Object? code = raw is Map<Object?, Object?>
          ? raw['errorCode']
          : null;
      throw ImageStoreFailure(_problemFor(code));
    } on PlatformException catch (error) {
      throw ImageStoreFailure(_problemFor(error.code));
    }
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
    Map<String, String> arguments,
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
    final Object? id = raw['id'];
    final Object? location = raw['location'];
    final Object? savedAt = raw['savedAt'];
    final Object? sizeBytes = raw['sizeBytes'];
    if (id is! String || location is! String) return null;
    if (savedAt is! int || sizeBytes is! int) return null;
    return PrivateImage(
      id: id,
      location: Uri.parse(location),
      savedAt: DateTime.fromMillisecondsSinceEpoch(savedAt),
      sizeBytes: sizeBytes,
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
        return StoredImage(location: Uri.parse(location), tier: tier);
      }
    }
    final Object? code = raw is Map<Object?, Object?> ? raw['errorCode'] : null;
    throw ImageStoreFailure(_problemFor(code));
  }

  ImageStoreProblem _problemFor(Object? code) {
    return switch (code) {
      'downloadFailed' => ImageStoreProblem.source,
      'unavailable' => ImageStoreProblem.unavailable,
      'notConfigured' => ImageStoreProblem.notConfigured,
      'restricted' => ImageStoreProblem.restricted,
      _ => ImageStoreProblem.unknown,
    };
  }
}
