import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/use_cases/confirm_nsfw_on_removable.dart';
import 'package:tela/features/settings/nsfw_removable_dialog.dart';

/// Gates a routing that would send explicit downloads to a removable card,
/// warning once and returning whether the caller may proceed with it.
///
/// This is slice 4's shared enforcement, called from both edges so neither
/// re-derives the risk (missing the folder-chooser edge is the easy bug): the
/// NSFW tier picker moving to files-outside-gallery, and the folder chooser
/// picking a removable card while NSFW already routes to files. The caller
/// passes the routing it is *about to* end up in — [nsfwTier] and whether the
/// folder that tier would write to is [folderRemovable].
///
/// Returns `true` when the routing is safe to keep — either no warning was
/// owed, or the user chose "Use card anyway", in which case the one-time
/// acknowledgement is persisted here. Returns `false` when the user declined
/// (or dismissed the dialog); the caller must then keep explicit downloads off
/// the card. How it does that differs by edge and is the caller's business:
/// the tier picker simply never applies the files tier, while the folder
/// chooser — whose SAF grant is already taken — routes NSFW to the private
/// tier instead.
Future<bool> confirmExplicitOnRemovable(
  WidgetRef ref,
  BuildContext context, {
  required StorageTier nsfwTier,
  required bool folderRemovable,
}) async {
  final ConfirmNsfwOnRemovable confirm = ref.read(
    confirmNsfwOnRemovableProvider,
  );
  final bool pending = await confirm.isPending(
    nsfwTier: nsfwTier,
    folderRemovable: folderRemovable,
  );
  if (!pending) return true;
  if (!context.mounted) return false;

  final bool useCard = await showNsfwRemovableWarning(context);
  if (useCard) await confirm.acknowledge();
  return useCard;
}
