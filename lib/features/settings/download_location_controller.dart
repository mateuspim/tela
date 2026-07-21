import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/download_location.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';
import 'package:tela/domain/ports/image_store.dart';

/// Where the files-outside-gallery tier writes, and the volumes on offer.
final AsyncNotifierProvider<DownloadLocationController, DownloadLocation>
downloadLocationProvider =
    AsyncNotifierProvider<DownloadLocationController, DownloadLocation>(
      DownloadLocationController.new,
    );

/// Reads the download location and opens the picker to move it to a volume.
///
/// Re-reading after the picker would be the safer-looking choice, but the
/// native side already describes the folder it just granted, so a second round
/// trip would only add a frame of blank row.
class DownloadLocationController extends AsyncNotifier<DownloadLocation> {
  @override
  Future<DownloadLocation> build() {
    return ref.watch(imageStoreProvider).downloadLocation();
  }

  /// Points downloads at [kind]'s volume, opening the picker to confirm it.
  ///
  /// A cancelled or unavailable pick leaves the previous location showing: the
  /// port answers null for both, and overwriting state with that would blank a
  /// folder the user never asked to clear. On success the card-available flag
  /// is re-read too, since inserting the card is what made this reachable.
  Future<void> choose(StorageVolumeKind kind) async {
    final ImageStore store = ref.read(imageStoreProvider);
    final DownloadFolder? chosen = await store.chooseDownloadFolder(kind);
    if (chosen == null) return;
    state = await AsyncValue.guard<DownloadLocation>(store.downloadLocation);
  }
}
