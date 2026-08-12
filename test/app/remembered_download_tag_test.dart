import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/remembered_download_tag.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';

import '../fakes/fake_settings_repository.dart';

/// The tag the chooser offers first — and the rule that it is **two** memories.
///
/// The split is a privacy decision, not an implementation detail: a tag chosen
/// for the private library must never reach `SettingEntries`, which lives in
/// the database Android's Auto Backup carries off the device. The 2026-08-12
/// exclusion took the private *images* off that path; a folder called "waifus"
/// in the settings table would put a description of them straight back on it.
void main() {
  late FakeSettingsRepository settings;
  late ProviderContainer container;

  setUp(() {
    settings = FakeSettingsRepository();
    container = ProviderContainer(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(settings),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<RememberedDownloadTag> loaded() async {
    await container.read(rememberedDownloadTagProvider.future);
    return container.read(rememberedDownloadTagProvider.notifier);
  }

  test('offers nothing before anything has been remembered', () async {
    final RememberedDownloadTag tags = await loaded();

    expect(tags.offeredFor(StorageTier.sharedGallery), isNull);
    expect(tags.offeredFor(StorageTier.appPrivate), isNull);
  });

  test('a shared-tier tag is persisted and offered back', () async {
    final RememberedDownloadTag tags = await loaded();

    await tags.remember(TagFolder('anime'), tier: StorageTier.sharedGallery);

    expect(await settings.loadDownloadTag(), TagFolder('anime'));
    expect(tags.offeredFor(StorageTier.sharedGallery), TagFolder('anime'));
    expect(
      tags.offeredFor(StorageTier.filesOutsideGallery),
      TagFolder('anime'),
    );
  });

  /// The load-bearing one. Held for the session, and nowhere a backup can read.
  test('a private-library tag never reaches the stored settings', () async {
    final RememberedDownloadTag tags = await loaded();

    await tags.remember(TagFolder('waifus'), tier: StorageTier.appPrivate);

    expect(
      await settings.loadDownloadTag(),
      isNull,
      reason: 'a private tag was written to the backed-up settings table',
    );
    expect(tags.offeredFor(StorageTier.appPrivate), TagFolder('waifus'));
  });

  /// Two tiers, two folders: the private library's `anime` and the gallery's
  /// are different directories, so suggesting one for the other would file a
  /// download somewhere the user did not point at.
  test('the two memories do not leak into each other', () async {
    final RememberedDownloadTag tags = await loaded();

    await tags.remember(TagFolder('waifus'), tier: StorageTier.appPrivate);
    await tags.remember(TagFolder('walls'), tier: StorageTier.sharedGallery);

    expect(tags.offeredFor(StorageTier.appPrivate), TagFolder('waifus'));
    expect(tags.offeredFor(StorageTier.sharedGallery), TagFolder('walls'));
  });

  test('remembering nothing clears the stored tag', () async {
    final RememberedDownloadTag tags = await loaded();
    await tags.remember(TagFolder('anime'), tier: StorageTier.sharedGallery);

    await tags.remember(null, tier: StorageTier.sharedGallery);

    expect(await settings.loadDownloadTag(), isNull);
    expect(tags.offeredFor(StorageTier.sharedGallery), isNull);
  });

  /// One intent, both memories: a user who stops the suggestion does not mean
  /// "except in the private library".
  test('forgetting clears both memories at once', () async {
    final RememberedDownloadTag tags = await loaded();
    await tags.remember(TagFolder('waifus'), tier: StorageTier.appPrivate);
    await tags.remember(TagFolder('walls'), tier: StorageTier.sharedGallery);

    await tags.forget();

    expect(tags.offeredFor(StorageTier.appPrivate), isNull);
    expect(tags.offeredFor(StorageTier.sharedGallery), isNull);
    expect(await settings.loadDownloadTag(), isNull);
  });
}
