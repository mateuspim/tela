import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/download_location.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';

void main() {
  group('volumeFor', () {
    // Regression, owner 2026-10-16: the private library never follows the
    // card the files tier is set to, and the chooser now says so.
    test('keeps the private library on the device with a card set', () {
      expect(
        _split.volumeFor(StorageTier.appPrivate, Purity.nsfw),
        StorageVolumeKind.device,
      );
    });

    test('keeps the gallery on the device with a card set', () {
      expect(
        _split.volumeFor(StorageTier.sharedGallery, Purity.sfw),
        StorageVolumeKind.device,
      );
    });

    test('follows each purity to its own folder for the files tier', () {
      expect(
        _split.volumeFor(StorageTier.filesOutsideGallery, Purity.sfw),
        StorageVolumeKind.device,
      );
      expect(
        _split.volumeFor(StorageTier.filesOutsideGallery, Purity.nsfw),
        StorageVolumeKind.sdCard,
      );
    });

    test('answers null for the files tier before any folder is granted', () {
      const DownloadLocation unset = DownloadLocation(
        folder: null,
        sdCardAvailable: true,
      );

      expect(
        unset.volumeFor(StorageTier.filesOutsideGallery, Purity.sfw),
        isNull,
      );
    });
  });

  group('folderFor', () {
    test('gives explicit downloads the explicit folder', () {
      expect(_split.folderFor(Purity.nsfw), _card);
    });

    test('gives sketchy downloads the safe folder', () {
      expect(_split.folderFor(Purity.sketchy), _device);
    });
  });

  group('offersSdCard', () {
    // An explicit folder on a card that has since been ejected must still be
    // shown as the user's choice, the same as a safe one.
    test('holds for an explicit folder on an ejected card', () {
      const DownloadLocation ejected = DownloadLocation(
        folder: _device,
        explicitFolder: _card,
        sdCardAvailable: false,
      );

      expect(ejected.offersSdCard, isTrue);
    });
  });
}

const DownloadFolder _device = DownloadFolder(
  volumeLabel: 'Internal storage',
  relativePath: 'Pictures/tela',
  isRemovable: false,
  isAvailable: true,
);

const DownloadFolder _card = DownloadFolder(
  volumeLabel: 'SD card',
  relativePath: 'Pictures/.tela',
  isRemovable: true,
  isAvailable: true,
);

/// Safe downloads on the device, explicit ones on the card.
const DownloadLocation _split = DownloadLocation(
  folder: _device,
  explicitFolder: _card,
  sdCardAvailable: true,
);
