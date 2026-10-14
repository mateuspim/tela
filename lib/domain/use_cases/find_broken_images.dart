import 'package:tela/domain/models/broken_image.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/stored_image_condition.dart';
import 'package:tela/domain/ports/download_history.dart';
import 'package:tela/domain/ports/image_store.dart';

/// How far an inspection has got: [done] of [total] files looked at.
typedef InspectionProgress = void Function(int done, int total);

/// Finds every stored image whose bytes are damaged, wherever tela keeps it.
///
/// Two listings cover every home there is: the download history names the
/// gallery and files-folder downloads, and the private library names its own
/// two homes — the app-private tier and the vault, on the device or on a card.
/// Explicit downloads write no history row, so the second listing is the only
/// way to reach them; it is also where the 0-byte offload leftovers that
/// prompted this were found (owner, 2026-10-07).
///
/// ```dart
/// final List<BrokenImage> broken = await findBrokenImages(onProgress: report);
/// ```
class FindBrokenImages {
  /// Creates the search over the storage and history seams.
  const FindBrokenImages({
    required ImageStore imageStore,
    required DownloadHistory history,
  }) : _imageStore = imageStore,
       _history = history;

  final ImageStore _imageStore;
  final DownloadHistory _history;

  /// How many files cross to the platform at a time — enough to amortise the
  /// round trip, few enough that the count on screen keeps moving.
  static const int _chunk = 200;

  /// The damaged images, history rows first, then the private library.
  Future<List<BrokenImage>> call({InspectionProgress? onProgress}) async {
    final List<BrokenImage> candidates = <BrokenImage>[
      for (final DownloadRecord record in await _history.downloads())
        _fromRecord(record),
      for (final PrivateImage image in await _imageStore.privateImages())
        _fromPrivate(image),
    ];
    final List<StoredImageCondition> conditions = await _inspect(
      candidates,
      onProgress,
    );
    return <BrokenImage>[
      for (int i = 0; i < candidates.length; i++)
        if (conditions[i].isBroken) candidates[i].withCondition(conditions[i]),
    ];
  }

  Future<List<StoredImageCondition>> _inspect(
    List<BrokenImage> candidates,
    InspectionProgress? onProgress,
  ) async {
    final List<StoredImageCondition> conditions = <StoredImageCondition>[];
    onProgress?.call(0, candidates.length);
    for (int at = 0; at < candidates.length; at += _chunk) {
      final int end = (at + _chunk).clamp(0, candidates.length);
      conditions.addAll(
        await _imageStore.inspectAll(<Uri>[
          for (final BrokenImage c in candidates.sublist(at, end)) c.location,
        ]),
      );
      onProgress?.call(end, candidates.length);
    }
    return conditions;
  }

  BrokenImage _fromRecord(DownloadRecord record) => BrokenImage(
    ref: record.wallpaper.ref,
    tier: record.tier,
    tag: record.tag,
    location: record.location,
    condition: StoredImageCondition.intact,
    recorded: true,
  );

  BrokenImage _fromPrivate(PrivateImage image) => BrokenImage(
    ref: image.ref,
    tier: image.tier,
    tag: image.tag,
    location: image.location,
    condition: StoredImageCondition.intact,
    recorded: false,
  );
}
