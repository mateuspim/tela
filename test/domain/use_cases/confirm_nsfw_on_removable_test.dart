import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/use_cases/confirm_nsfw_on_removable.dart';

import '../../fakes/fake_settings_repository.dart';

void main() {
  group('ConfirmNsfwOnRemovable.isNeeded', () {
    test(
      'is true only for unacknowledged explicit files on a removable card',
      () {
        expect(
          ConfirmNsfwOnRemovable.isNeeded(
            nsfwTier: StorageTier.filesOutsideGallery,
            folderRemovable: true,
            acknowledged: false,
          ),
          isTrue,
        );
      },
    );

    test('is false once acknowledged, even on a removable card', () {
      expect(
        ConfirmNsfwOnRemovable.isNeeded(
          nsfwTier: StorageTier.filesOutsideGallery,
          folderRemovable: true,
          acknowledged: true,
        ),
        isFalse,
      );
    });

    test('is false when the folder is not removable', () {
      expect(
        ConfirmNsfwOnRemovable.isNeeded(
          nsfwTier: StorageTier.filesOutsideGallery,
          folderRemovable: false,
          acknowledged: false,
        ),
        isFalse,
      );
    });

    test('is false when explicit downloads do not route to the files tier', () {
      // The private tier is safe on a card — it never writes there — so being
      // removable is beside the point unless the files tier is in play.
      expect(
        ConfirmNsfwOnRemovable.isNeeded(
          nsfwTier: StorageTier.appPrivate,
          folderRemovable: true,
          acknowledged: false,
        ),
        isFalse,
      );
    });
  });

  group('ConfirmNsfwOnRemovable.isPending', () {
    test('reads the acknowledgement from the settings it was given', () async {
      final FakeSettingsRepository settings = FakeSettingsRepository(
        settings: StorageSettings(
          sfwTier: StorageTier.filesOutsideGallery,
          nsfwTier: StorageTier.filesOutsideGallery,
        ),
      );
      final ConfirmNsfwOnRemovable confirm = ConfirmNsfwOnRemovable(settings);

      expect(
        await confirm.isPending(
          nsfwTier: StorageTier.filesOutsideGallery,
          folderRemovable: true,
        ),
        isTrue,
      );

      await confirm.acknowledge();

      expect(
        await confirm.isPending(
          nsfwTier: StorageTier.filesOutsideGallery,
          folderRemovable: true,
        ),
        isFalse,
      );
    });
  });

  test('acknowledge persists the one-time nod', () async {
    final FakeSettingsRepository settings = FakeSettingsRepository();
    await ConfirmNsfwOnRemovable(settings).acknowledge();

    expect(settings.nsfwOnRemovableAckSaved, isTrue);
  });
}
