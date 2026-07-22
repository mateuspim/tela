import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// The one-time confirmation before explicit downloads reach a removable card.
///
/// A removable card defeats every protection the private tier gives: pull it
/// out and read it anywhere — no app-lock, no secure flag. The owner chose to
/// allow it (the desktop-sync path is why the files-outside-gallery tier
/// exists, and refusing would break card-based Omarchy syncing) but to confirm
/// once. This owns the rule for whether that confirmation is still owed.
///
/// The predicate [isNeeded] is pure and static so the truth table is
/// unit-testable without a repository; [isPending] wires it to the persisted
/// acknowledgement.
///
/// ```dart
/// if (await confirm.isPending(nsfwTier: tier, folderRemovable: true)) {
///   // warn, then confirm.acknowledge() or route NSFW to the private tier
/// }
/// ```
class ConfirmNsfwOnRemovable {
  /// Creates the use case over the settings the acknowledgement persists in.
  const ConfirmNsfwOnRemovable(this._settings);

  final SettingsRepository _settings;

  /// Whether this routing needs the warning, given a prior [acknowledged] nod.
  ///
  /// True only when explicit downloads route to the files-outside-gallery tier
  /// *and* that folder sits on a removable card *and* the user has not yet
  /// acknowledged it. Pure so both edges — the NSFW tier picker and the folder
  /// chooser — share one definition of the risk, rather than each re-deriving a
  /// boolean and one of them getting it wrong.
  static bool isNeeded({
    required StorageTier nsfwTier,
    required bool folderRemovable,
    required bool acknowledged,
  }) {
    if (acknowledged) return false;
    if (nsfwTier != StorageTier.filesOutsideGallery) return false;
    return folderRemovable;
  }

  /// Whether the current configuration still owes the confirmation.
  ///
  /// Reads the persisted acknowledgement; the caller supplies the routing it
  /// is about to end up in, so this answers for the *pending* state rather than
  /// the last-saved one.
  Future<bool> isPending({
    required StorageTier nsfwTier,
    required bool folderRemovable,
  }) async {
    return isNeeded(
      nsfwTier: nsfwTier,
      folderRemovable: folderRemovable,
      acknowledged: await _settings.loadNsfwOnRemovableAcknowledged(),
    );
  }

  /// Records the user's one-time acknowledgement, so the warning never fires
  /// again.
  Future<void> acknowledge() =>
      _settings.saveNsfwOnRemovableAcknowledged(acknowledged: true);
}
