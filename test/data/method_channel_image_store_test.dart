import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/storage/method_channel_image_store.dart';
import 'package:tela/domain/models/download_deletion.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/download_location.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';
import 'package:tela/domain/models/stored_image_size.dart';
import 'package:tela/domain/models/vault_folder.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

void main() {
  test('sends image identity, purity, and tier to the native store', () async {
    final _FakeImageStoreChannel fake = _FakeImageStoreChannel();
    final MethodChannelImageStore store = MethodChannelImageStore(
      invokeMethod: fake.call,
    );

    await store.store(
      source: SourceId.konachan,
      id: 'e7jvjd',
      imageUrl: _imageUrl,
      purity: Purity.nsfw,
      tier: StorageTier.appPrivate,
    );

    expect(fake.receivedMethod, 'storeImage');
    // The source travels beside the id because native composes the file name
    // from the pair; without it every Konachan download was filed under
    // Wallhaven's name on disk.
    expect(fake.receivedArguments, <String, String>{
      'source': 'konachan',
      'id': 'e7jvjd',
      'imageUrl': _imageUrl,
      'purity': 'nsfw',
      'tier': 'appPrivate',
    });
  });

  test('maps native failures without retaining a sensitive location', () async {
    const Map<String, ImageStoreProblem> cases = <String, ImageStoreProblem>{
      'downloadFailed': ImageStoreProblem.source,
      'unavailable': ImageStoreProblem.unavailable,
      'notConfigured': ImageStoreProblem.notConfigured,
      'folderUnavailable': ImageStoreProblem.folderUnavailable,
      'restricted': ImageStoreProblem.restricted,
      'newNativeFailure': ImageStoreProblem.unknown,
    };

    for (final MapEntry<String, ImageStoreProblem> entry in cases.entries) {
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel(
        response: <Object?, Object?>{
          'success': false,
          'errorCode': entry.key,
          'unsafeDebugValue': _imageUrl,
        },
      );
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: fake.call,
      );

      await expectLater(
        store.store(
          source: SourceId.wallhaven,
          id: 'e7jvjd',
          imageUrl: _imageUrl,
          purity: Purity.nsfw,
          tier: StorageTier.sharedGallery,
        ),
        throwsA(_failureWith(entry.value)),
      );
    }
  });

  test('maps a platform exception to a safe storage failure', () async {
    final MethodChannelImageStore store = MethodChannelImageStore(
      invokeMethod: _FakeImageStoreChannel(
        platformError: PlatformException(code: 'notConfigured'),
      ).call,
    );

    await expectLater(
      store.store(
        source: SourceId.wallhaven,
        id: 'e7jvjd',
        imageUrl: _imageUrl,
        purity: Purity.sfw,
        tier: StorageTier.filesOutsideGallery,
      ),
      throwsA(_failureWith(ImageStoreProblem.notConfigured)),
    );
  });

  group('privateImages', () {
    test('maps the native listing into domain images', () async {
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel(
        response: <Object?, Object?>{
          'success': true,
          'images': <Object?>[
            <Object?, Object?>{
              'ref': 'wallhaven-e7jvjd',
              'location':
                  'file:///data/user/0/cc.pym.tela/files/wallhaven-e7jvjd.jpg',
              'savedAt': 1750000000000,
              'sizeBytes': 2048,
              'width': 1080,
              'height': 2400,
            },
          ],
        },
      );
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: fake.call,
      );

      final List<PrivateImage> images = await store.privateImages();

      expect(fake.receivedMethod, 'listPrivateImages');
      expect(
        images.single.ref,
        const WallpaperRef(SourceId.wallhaven, 'e7jvjd'),
      );
      expect(images.single.sizeBytes, 2048);
      expect(images.single.width, 1080);
      expect(images.single.height, 2400);
      expect(images.single.aspectRatio, closeTo(1080 / 2400, 1e-9));
      expect(
        images.single.savedAt,
        DateTime.fromMillisecondsSinceEpoch(1750000000000),
      );
    });

    /// A different method on the wire, because it is a different walk: the
    /// vault sits on a card and costs a crossing per file, and the offload
    /// survey has no use for a single one of them.
    test('the app-private listing asks the narrower method', () async {
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel(
        response: <Object?, Object?>{
          'success': true,
          'images': <Object?>[
            <Object?, Object?>{
              'ref': 'wallhaven-e7jvjd',
              'location': '/data/user/0/cc.pym.tela/files/private/x.jpg',
              'savedAt': 1750000000000,
              'sizeBytes': 2048,
            },
          ],
        },
      );
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: fake.call,
      );

      final List<PrivateImage> images = await store.appPrivateImages();

      expect(fake.receivedMethod, 'listAppPrivateImages');
      expect(images.single.tier, StorageTier.appPrivate);
    });

    test('a corrupt file lists with unknown, safe dimensions', () async {
      // The native bounds decode answers -1 for a file it cannot read; the row
      // must still list (so the library is not emptied) but carry no ratio, so
      // the gallery falls back to a square, broken-image state rather than
      // dividing by an unknown dimension.
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{
            'success': true,
            'images': <Object?>[
              <Object?, Object?>{
                'ref': 'wallhaven-corrupt',
                'location': 'file:///files/wallhaven-corrupt.jpg',
                'savedAt': 1750000000000,
                'sizeBytes': 8,
                'width': -1,
                'height': -1,
              },
            ],
          },
        ).call,
      );

      final PrivateImage image = (await store.privateImages()).single;

      expect(image.ref.id, 'corrupt');
      expect(image.width, isNull);
      expect(image.height, isNull);
      expect(image.aspectRatio, isNull);
    });

    test('an empty tier lists nothing rather than failing', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{'success': true, 'images': <Object?>[]},
        ).call,
      );

      expect(await store.privateImages(), isEmpty);
    });

    test('skips a mangled entry instead of emptying the library', () async {
      // One unreadable row must not read as "all my files are gone".
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{
            'success': true,
            'images': <Object?>[
              <Object?, Object?>{'ref': 'broken'},
              <Object?, Object?>{
                'ref': 'wallhaven-intact',
                'location': 'file:///files/wallhaven-intact.jpg',
                'savedAt': 1750000000000,
                'sizeBytes': 1,
              },
            ],
          },
        ).call,
      );

      final List<PrivateImage> images = await store.privateImages();

      expect(
        images.map((PrivateImage image) => image.ref.id),
        <String>['intact'],
      );
    });

    test('maps a native listing failure to a safe failure', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{
            'success': false,
            'errorCode': 'unavailable',
          },
        ).call,
      );

      await expectLater(
        store.privateImages(),
        throwsA(_failureWith(ImageStoreProblem.unavailable)),
      );
    });
  });

  group('deleteDownload', () {
    const String location = 'content://media/external/images/media/42';

    test('sends the tier and location, and reads the deleted result', () async {
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel(
        response: <Object?, Object?>{
          'success': true,
          'deleted': <String>[location],
        },
      );
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: fake.call,
      );

      final DownloadDeletion outcome = await store.deleteDownload(
        tier: StorageTier.sharedGallery,
        location: Uri.parse(location),
      );

      expect(outcome, DownloadDeletion.deleted);
      expect(fake.receivedMethod, 'deleteDownload');
      expect(fake.receivedArguments, <String, String>{
        'tier': 'sharedGallery',
        'location': location,
      });
    });

    test('an empty result is the user declining the prompt', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{'success': true, 'deleted': <String>[]},
        ).call,
      );

      final DownloadDeletion outcome = await store.deleteDownload(
        tier: StorageTier.sharedGallery,
        location: Uri.parse(location),
      );

      expect(outcome, DownloadDeletion.declined);
    });

    test('maps a refused delete to a safe failure', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{
            'success': false,
            'errorCode': 'unavailable',
          },
        ).call,
      );

      await expectLater(
        store.deleteDownload(
          tier: StorageTier.filesOutsideGallery,
          location: Uri.parse('content://tree/doc/1'),
        ),
        throwsA(_failureWith(ImageStoreProblem.unavailable)),
      );
    });
  });

  group('deleteDownloads', () {
    test('sends the whole batch and returns the deleted locations', () async {
      const String gallery = 'content://media/external/images/media/1';
      const String document = 'content://tree/doc/2';
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel(
        // The gallery item was declined; only the document came back.
        response: <Object?, Object?>{
          'success': true,
          'deleted': <String>[document],
        },
      );
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: fake.call,
      );

      final Set<Uri> deleted = await store.deleteDownloads(
        <({StorageTier tier, Uri location})>[
          (tier: StorageTier.sharedGallery, location: Uri.parse(gallery)),
          (
            tier: StorageTier.filesOutsideGallery,
            location: Uri.parse(document),
          ),
        ],
      );

      expect(deleted, <Uri>{Uri.parse(document)});
      expect(fake.receivedMethod, 'deleteDownloads');
      expect(fake.receivedArguments, <String, Object?>{
        'items': <Map<String, String>>[
          <String, String>{'tier': 'sharedGallery', 'location': gallery},
          <String, String>{'tier': 'filesOutsideGallery', 'location': document},
        ],
      });
    });

    test('an empty batch never touches the channel', () async {
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel();
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: fake.call,
      );

      final Set<Uri> deleted = await store.deleteDownloads(
        const <({StorageTier tier, Uri location})>[],
      );

      expect(deleted, isEmpty);
      expect(fake.receivedMethod, isNull);
    });
  });

  group('galleryDeleteConfirmedBySystem', () {
    test('reports whether the platform confirms a gallery delete', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{'confirmed': true},
        ).call,
      );

      expect(await store.galleryDeleteConfirmedBySystem(), isTrue);
    });

    test('guesses false when the native side cannot answer', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: (String method, Map<String, Object?> arguments) =>
            throw PlatformException(code: 'error'),
      );

      expect(await store.galleryDeleteConfirmedBySystem(), isFalse);
    });
  });

  group('canRead', () {
    test('asks the native side about the location', () async {
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel(
        response: <Object?, Object?>{'success': true, 'readable': true},
      );
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: fake.call,
      );

      expect(await store.canRead(Uri.parse('content://media/images/42')), true);
      expect(fake.receivedMethod, 'canReadImage');
      expect(fake.receivedArguments, <String, String>{
        'location': 'content://media/images/42',
      });
    });

    test('a file that will not open reads as gone', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{'success': true, 'readable': false},
        ).call,
      );

      expect(await store.canRead(Uri.parse('file:///gone.jpg')), false);
    });

    test('a native error costs the badge, not the screen', () async {
      // The one caller draws a tile with this. A history row whose file is gone
      // still sets its wallpaper by re-fetching, so a probe that blows up must
      // never take the download history down with it — and "unreadable" is the
      // safe guess anyway: at worst it warns about a file that is still there.
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          platformError: PlatformException(code: 'unavailable'),
        ).call,
      );

      expect(await store.canRead(Uri.parse('file:///gone.jpg')), false);
    });
  });

  group("the private library's two homes", () {
    Map<Object?, Object?> listing(Map<Object?, Object?> row) =>
        <Object?, Object?>{
          'success': true,
          'images': <Object?>[
            <Object?, Object?>{
              'ref': 'wallhaven-abc123',
              'location': 'file:///data/wallhaven-abc123.jpg',
              'savedAt': 1000,
              'sizeBytes': 2048,
              ...row,
            },
          ],
        };

    Future<PrivateImage> read(Map<Object?, Object?> row) async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(response: listing(row)).call,
      );
      return (await store.privateImages()).single;
    }

    test('a vault row keeps the tier its delete has to route by', () async {
      final PrivateImage image = await read(<Object?, Object?>{
        'tier': 'filesOutsideGallery',
      });

      expect(image.tier, StorageTier.filesOutsideGallery);
    });

    // Every row was app-private before the vault existed, so a payload with no
    // tier on it is not ambiguous — it is old, and old means app-private.
    test('a row with no tier reads as app-private', () async {
      expect((await read(<Object?, Object?>{})).tier, StorageTier.appPrivate);
    });

    /// This value routes a **delete**, and the gallery is the one tier that
    /// must never be reachable that way — so an unexpected name is not trusted.
    test('a row naming the gallery is not believed', () async {
      final PrivateImage image = await read(<Object?, Object?>{
        'tier': 'sharedGallery',
      });

      expect(image.tier, StorageTier.appPrivate);
    });
  });

  group('setVaultFolder', () {
    test('sends the label without its dot', () async {
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel(
        response: <Object?, Object?>{'success': true},
      );

      final bool saved = await MethodChannelImageStore(
        invokeMethod: fake.call,
      ).setVaultFolder(VaultFolder('stash'));

      expect(saved, isTrue);
      expect(fake.receivedMethod, 'setVaultFolder');
      expect(fake.receivedArguments, <String, Object>{'label': 'stash'});
    });

    test('a refusal is answered false, never thrown', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          platformError: PlatformException(code: 'unavailable'),
        ).call,
      );

      expect(await store.setVaultFolder(VaultFolder('stash')), isFalse);
    });

    /// The row draws from this, and a label the platform reports that this side
    /// would refuse must cost accuracy for a frame rather than the whole row.
    test('an unusable reported label reads as the standard vault', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{
            'success': true,
            'sdCardAvailable': false,
            'vaultLabel': '../secrets',
          },
        ).call,
      );

      expect((await store.downloadLocation()).vault, VaultFolder.standard);
    });

    test('a reported label is carried through', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{
            'success': true,
            'sdCardAvailable': false,
            'vaultLabel': 'stash',
          },
        ).call,
      );

      expect((await store.downloadLocation()).vault, VaultFolder('stash'));
    });
  });

  group('measureAll', () {
    test('sizes every location in one crossing', () async {
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel(
        response: <Object?, Object?>{
          'success': true,
          'bytes': <Object?>[2048, 4096],
          'removable': <Object?>[false, true],
        },
      );
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: fake.call,
      );

      final List<StoredImageSize> sizes = await store.measureAll(<Uri>[
        Uri.parse('file:///a.jpg'),
        Uri.parse('file:///b.jpg'),
      ]);

      expect(sizes.first.bytes, 2048);
      expect(sizes.first.onRemovableVolume, isFalse);
      expect(sizes.last.onRemovableVolume, isTrue);
      expect(fake.receivedMethod, 'measureImages');
    });

    // Same index-pairing contract the readable flags carry: a short reply must
    // not shift one row's size onto another's tally.
    test('a short or malformed reply reads as unmeasurable', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{
            'success': true,
            'bytes': <Object?>[10],
          },
        ).call,
      );

      expect(
        await store.measureAll(<Uri>[
          Uri.parse('file:///a.jpg'),
          Uri.parse('file:///b.jpg'),
        ]),
        <StoredImageSize>[
          const StoredImageSize(bytes: 10, onRemovableVolume: false),
          StoredImageSize.zero,
        ],
      );
    });

    test('a native error costs the figures, not the screen', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          platformError: PlatformException(code: 'unavailable'),
        ).call,
      );

      expect(
        await store.measureAll(<Uri>[Uri.parse('file:///a.jpg')]),
        <StoredImageSize>[StoredImageSize.zero],
      );
    });

    test('an empty request never crosses the channel', () async {
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel(
        response: <Object?, Object?>{'success': true},
      );

      expect(
        await MethodChannelImageStore(invokeMethod: fake.call).measureAll(
          <Uri>[],
        ),
        isEmpty,
      );
      expect(fake.receivedMethod, isNull);
    });
  });

  group('canReadAll', () {
    test('asks about every location in one crossing', () async {
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel(
        response: <Object?, Object?>{
          'success': true,
          'readable': <Object?>[true, false, true],
        },
      );
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: fake.call,
      );

      final List<bool> readable = await store.canReadAll(<Uri>[
        Uri.parse('file:///a.jpg'),
        Uri.parse('file:///b.jpg'),
        Uri.parse('file:///c.jpg'),
      ]);

      expect(readable, <bool>[true, false, true]);
      expect(fake.receivedMethod, 'canReadImages');
      expect(fake.receivedArguments, <String, Object>{
        'locations': <String>[
          'file:///a.jpg',
          'file:///b.jpg',
          'file:///c.jpg',
        ],
      });
    });

    // The caller pairs these with its records **by index**, so a reply of the
    // wrong length must never come back as a shorter list — it would shift
    // every answer after the gap and badge the wrong wallpapers as missing.
    test('a short reply is padded, never returned short', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{
            'success': true,
            'readable': <Object?>[true],
          },
        ).call,
      );

      expect(
        await store.canReadAll(<Uri>[
          Uri.parse('file:///a.jpg'),
          Uri.parse('file:///b.jpg'),
          Uri.parse('file:///c.jpg'),
        ]),
        <bool>[true, false, false],
      );
    });

    test('a malformed reply reads as all gone', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{'success': true, 'readable': 'nonsense'},
        ).call,
      );

      expect(
        await store.canReadAll(<Uri>[
          Uri.parse('file:///a.jpg'),
          Uri.parse('file:///b.jpg'),
        ]),
        <bool>[false, false],
      );
    });

    test('a native error costs the badges, not the screen', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          platformError: PlatformException(code: 'unavailable'),
        ).call,
      );

      expect(
        await store.canReadAll(<Uri>[Uri.parse('file:///a.jpg')]),
        <bool>[false],
      );
    });

    test('an empty history never crosses to the platform at all', () async {
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel();
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: fake.call,
      );

      expect(await store.canReadAll(const <Uri>[]), isEmpty);
      expect(fake.receivedMethod, isNull);
    });
  });

  group('download location', () {
    Map<Object?, Object?> folderPayload({
      String label = 'SD card',
      String path = 'Wallpapers/tela',
      bool removable = true,
      bool available = true,
      int? freeBytes = 8589934592,
    }) => <Object?, Object?>{
      'volumeLabel': label,
      'relativePath': path,
      'isRemovable': removable,
      'isAvailable': available,
      'freeBytes': ?freeBytes,
    };

    test('maps the folder and card availability off the payload', () async {
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel(
        response: <Object?, Object?>{
          'success': true,
          'sdCardAvailable': true,
          'folder': folderPayload(),
        },
      );
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: fake.call,
      );

      final DownloadLocation location = await store.downloadLocation();

      expect(fake.receivedMethod, 'describeDownloadLocation');
      expect(location.sdCardAvailable, true);
      expect(location.folder?.volumeLabel, 'SD card');
      expect(location.folder?.relativePath, 'Wallpapers/tela');
      expect(location.folder?.isRemovable, true);
      expect(location.folder?.freeBytes, 8589934592);
      expect(location.currentKind, StorageVolumeKind.sdCard);
    });

    test('a card present but no folder chosen is a null folder', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: const <Object?, Object?>{
            'success': true,
            'sdCardAvailable': true,
          },
        ).call,
      );

      final DownloadLocation location = await store.downloadLocation();

      // Not an error: an unconfigured tier still has to report the card so the
      // row can offer it before anything is granted.
      expect(location.folder, isNull);
      expect(location.sdCardAvailable, true);
      expect(location.offersSdCard, true);
    });

    test('keeps an unavailable folder rather than dropping it', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{
            'success': true,
            'sdCardAvailable': false,
            'folder': folderPayload(available: false, freeBytes: null),
          },
        ).call,
      );

      final DownloadLocation location = await store.downloadLocation();

      // An ejected card is still the configured folder, and still offered even
      // though `sdCardAvailable` is false — offersSdCard reads it off folder.
      expect(location.folder?.isAvailable, false);
      expect(location.offersSdCard, true);
    });

    test('reports no free space rather than zero when unread', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: <Object?, Object?>{
            'success': true,
            'sdCardAvailable': false,
            'folder': folderPayload(
              label: 'Internal storage',
              path: 'tela',
              removable: false,
              freeBytes: null,
            ),
          },
        ).call,
      );

      final DownloadLocation location = await store.downloadLocation();

      expect(location.folder?.freeBytes, isNull);
      expect(location.currentKind, StorageVolumeKind.device);
    });

    test('an unusable payload is empty, not a crash', () async {
      final List<Object?> responses = <Object?>[
        <Object?, Object?>{'success': false},
        <Object?, Object?>{'success': true, 'folder': 'not a map'},
        'not a map',
        null,
      ];

      for (final Object? response in responses) {
        final MethodChannelImageStore store = MethodChannelImageStore(
          invokeMethod: _FakeImageStoreChannel(response: response).call,
        );

        final DownloadLocation location = await store.downloadLocation();
        expect(location.folder, isNull, reason: '$response');
        expect(location.sdCardAvailable, false, reason: '$response');
      }
    });

    test('a thrown platform channel yields an empty location', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          platformError: PlatformException(code: 'unavailable'),
        ).call,
      );

      final DownloadLocation location = await store.downloadLocation();
      expect(location.folder, isNull);
      expect(location.sdCardAvailable, false);
    });

    test('choosing sends the kind and maps the granted folder', () async {
      final _FakeImageStoreChannel fake = _FakeImageStoreChannel(
        response: <Object?, Object?>{
          'success': true,
          'sdCardAvailable': true,
          'folder': folderPayload(path: 'tela'),
        },
      );
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: fake.call,
      );

      final DownloadFolder? folder = await store.chooseDownloadFolder(
        StorageVolumeKind.sdCard,
      );

      expect(fake.receivedMethod, 'chooseDownloadFolder');
      expect(fake.receivedArguments, <String, String>{'kind': 'sdCard'});
      expect(folder?.volumeLabel, 'SD card');
    });

    test('a cancelled or absent pick answers null, not a folder', () async {
      final MethodChannelImageStore store = MethodChannelImageStore(
        invokeMethod: _FakeImageStoreChannel(
          response: const <Object?, Object?>{
            'success': false,
            'errorCode': 'notConfigured',
          },
        ).call,
      );

      expect(
        await store.chooseDownloadFolder(StorageVolumeKind.device),
        isNull,
      );
    });
  });
}

Matcher _failureWith(ImageStoreProblem problem) {
  return isA<ImageStoreFailure>()
      .having(
        (ImageStoreFailure failure) => failure.problem,
        'problem',
        problem,
      )
      .having(
        (ImageStoreFailure failure) => failure.toString(),
        'safe text',
        isNot(contains(_imageUrl)),
      );
}

const String _imageUrl = 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg';

class _FakeImageStoreChannel {
  _FakeImageStoreChannel({
    this.response = const <Object?, Object?>{
      'success': true,
      'location': 'content://cc.pym.tela/image/e7jvjd',
    },
    this.platformError,
  });

  final Object? response;
  final PlatformException? platformError;
  String? receivedMethod;
  Map<String, Object?>? receivedArguments;

  Future<Object?> call(String method, Map<String, Object?> arguments) async {
    receivedMethod = method;
    receivedArguments = arguments;
    final PlatformException? toThrow = platformError;
    if (toThrow != null) throw toThrow;
    return response;
  }
}
