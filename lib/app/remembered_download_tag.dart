import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';

/// The tag the chooser offers first, and the one place it is read or changed.
///
/// A controller rather than two calls to `SettingsRepository`, for the reason
/// `PinnedDownloadTier` is one: the chooser both reads this and writes it, and
/// a value with two owners is a value the screen offering to change it can
/// read a stale copy of.
///
/// **Two memories, not one, and the split is a privacy rule rather than a
/// convenience.** A tag chosen for a shared tier is persisted through
/// `SettingsRepository`; a tag chosen for the **private library** is held in
/// this notifier and dies with the process. `SettingEntries` lives in the
/// database Android's Auto Backup carries off the device, and a private
/// library's folder names say roughly what its file paths say — which is the
/// exposure the 2026-08-12 backup exclusion closed for the images themselves.
/// Re-typing a private tag once per session is the price, and it is a decision,
/// not a gap to be closed later.
///
/// ```dart
/// final TagFolder? first = ref.watch(rememberedDownloadTagProvider).value;
/// await ref.read(rememberedDownloadTagProvider.notifier).remember(
///   tag,
///   tier: StorageTier.sharedGallery,
/// );
/// ```
final AsyncNotifierProvider<RememberedDownloadTag, TagFolder?>
rememberedDownloadTagProvider =
    AsyncNotifierProvider<RememberedDownloadTag, TagFolder?>(
      RememberedDownloadTag.new,
    );

/// Loads the remembered tag and writes changes back through the port.
class RememberedDownloadTag extends AsyncNotifier<TagFolder?> {
  /// The private library's last tag, for this process only. Never persisted.
  TagFolder? _privateTag;

  @override
  Future<TagFolder?> build() {
    return ref.watch(settingsRepositoryProvider).loadDownloadTag();
  }

  /// The tag to offer first for a download headed to [tier].
  ///
  /// The private tier answers from memory and the shared ones from the stored
  /// value, so a tag typed for the private library is never suggested on a
  /// screen outside it — and vice versa, since the two tiers' folders are
  /// genuinely different places.
  TagFolder? offeredFor(StorageTier tier) {
    if (tier == StorageTier.appPrivate) return _privateTag;
    return state.value;
  }

  /// Remembers [tag] as the one to offer next, for downloads to [tier].
  ///
  /// Persists it only for the shared tiers; see the class docstring for why the
  /// private one stops at this object.
  Future<void> remember(TagFolder? tag, {required StorageTier tier}) async {
    if (tier == StorageTier.appPrivate) {
      _privateTag = tag;
      return;
    }
    // Persisted before published, as the pin is: a chooser that closed on a tag
    // which did not save would be a memory the user believes they have.
    await ref.read(settingsRepositoryProvider).setDownloadTag(tag);
    state = AsyncData<TagFolder?>(tag);
  }

  /// Stops offering a tag first, for both memories at once.
  ///
  /// One call rather than two because "stop suggesting a tag" is one intent,
  /// and a user who clears it in Settings does not mean "except in the private
  /// library".
  Future<void> forget() async {
    _privateTag = null;
    await ref.read(settingsRepositoryProvider).setDownloadTag(null);
    state = const AsyncData<TagFolder?>(null);
  }
}
