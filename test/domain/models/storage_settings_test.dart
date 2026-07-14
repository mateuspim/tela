import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';

void main() {
  group('StorageSettings', () {
    test('defaults keep safe content visible and explicit content private', () {
      expect(StorageSettings.defaults.sfwTier, StorageTier.sharedGallery);
      expect(StorageSettings.defaults.nsfwTier, StorageTier.appPrivate);
    });

    test('routes sketchy with sfw, not with nsfw', () {
      final StorageSettings settings = StorageSettings(
        sfwTier: StorageTier.filesOutsideGallery,
        nsfwTier: StorageTier.appPrivate,
      );

      expect(settings.tierFor(Purity.sfw), StorageTier.filesOutsideGallery);
      expect(settings.tierFor(Purity.sketchy), StorageTier.filesOutsideGallery);
      expect(settings.tierFor(Purity.nsfw), StorageTier.appPrivate);
    });

    test('rejects an nsfw tier that would MediaStore-index the file', () {
      expect(
        () => StorageSettings(
          sfwTier: StorageTier.sharedGallery,
          nsfwTier: StorageTier.sharedGallery,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            contains('sharedGallery'),
          ),
        ),
      );
    });

    test('copyWith rejects an nsfw tier that would index the file', () {
      expect(
        () => StorageSettings.defaults.copyWith(
          nsfwTier: StorageTier.sharedGallery,
        ),
        throwsArgumentError,
      );
    });

    test('offers the gallery to sfw, and withholds it from nsfw', () {
      expect(
        StorageSettings.choicesFor(Purity.sfw),
        contains(StorageTier.sharedGallery),
      );
      expect(
        StorageSettings.choicesFor(Purity.sketchy),
        contains(StorageTier.sharedGallery),
      );
      expect(
        StorageSettings.choicesFor(Purity.nsfw),
        <StorageTier>[StorageTier.filesOutsideGallery, StorageTier.appPrivate],
      );
    });
  });
}
