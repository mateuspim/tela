import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/use_cases/resolve_beam_files.dart';

import '../../fakes/fake_local_preview_cache.dart';

PrivateImage _image(
  String id, {
  required Uri location,
  StorageTier tier = StorageTier.appPrivate,
}) {
  return PrivateImage(
    ref: WallpaperRef(SourceId.wallhaven, id),
    location: location,
    savedAt: DateTime(2026, 8, 26),
    sizeBytes: 1024,
    tier: tier,
  );
}

List<BeamCandidate> _private(List<PrivateImage> images) => <BeamCandidate>[
  for (final PrivateImage image in images) BeamCandidate.ofPrivate(image),
];

/// A wallpaper as a source publishes one, with no file on the device.
final Wallpaper _wallpaper = Wallpaper(
  id: 'e7jvjd',
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/e7jvjd'),
  fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/e7jvjd.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg',
  resolution: const Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);

final Uri _appPrivate = Uri.parse('file:///data/tela/wallhaven-aaaaaa.jpg');
final Uri _vault = Uri.parse('content://com.android.externalstorage/doc/1');

void main() {
  group('resolving a beam batch', () {
    test('materializes a vault SAF URI rather than opening it', () async {
      // The whole reason this use case exists: File.fromUri throws
      // synchronously on a content: URI, which is what turned every vault tile
      // grey. A beam must never see one.
      final FakeLocalPreviewCache previews = FakeLocalPreviewCache();

      final ResolvedBeamFiles resolved = await ResolveBeamFiles(
        previews,
      ).call(_private(<PrivateImage>[_image('aaaaaa', location: _vault)]));

      expect(previews.materialised, <Uri>[_vault]);
      expect(resolved.files.single.path, startsWith('/cache/preview-'));
    });

    test('skips a file that will not materialize, keeping the rest', () async {
      // One unreadable image out of forty should cost itself, not the other
      // thirty-nine.
      final FakeLocalPreviewCache previews = FakeLocalPreviewCache(
        unreadable: <Uri>{_vault},
      );

      final ResolvedBeamFiles resolved = await ResolveBeamFiles(previews).call(
        _private(<PrivateImage>[
          _image('aaaaaa', location: _vault),
          _image('bbbbbb', location: _appPrivate),
        ]),
      );

      expect(resolved.files, hasLength(1));
      expect(resolved.files.single.id, 'wallhaven-bbbbbb');
    });

    test(
      'keys a file by source and id, so two sources cannot collide',
      () async {
        final ResolvedBeamFiles resolved =
            await ResolveBeamFiles(
              FakeLocalPreviewCache(),
            ).call(
              _private(<PrivateImage>[_image('aaaaaa', location: _appPrivate)]),
            );

        expect(resolved.files.single.id, 'wallhaven-aaaaaa');
      },
    );
  });

  group('a wallpaper nobody downloaded', () {
    test('is fetched on the way out rather than skipped', () async {
      // The whole reason a browse selection can beam at all: a beam sends
      // bytes, and a wallpaper being looked at has none on the device yet.
      final FakeLocalPreviewCache previews = FakeLocalPreviewCache();

      final ResolvedBeamFiles resolved = await ResolveBeamFiles(previews).call(
        <BeamCandidate>[BeamCandidate.ofWallpaper(_wallpaper)],
      );

      expect(previews.fetched, <Uri>[Uri.parse(_wallpaper.fullImageUrl)]);
      // Never through the local path: that one cannot read an http URL.
      expect(previews.materialised, isEmpty);
      expect(resolved.files.single.fileName, 'wallhaven-e7jvjd.jpg');
    });

    test('its fetched copy is always released', () async {
      // Unlike a download's own file, this one is tela's copy — leaving it
      // behind is a full-size wallpaper of cache per beam.
      final FakeLocalPreviewCache previews = FakeLocalPreviewCache();
      final ResolvedBeamFiles resolved = await ResolveBeamFiles(previews).call(
        <BeamCandidate>[BeamCandidate.ofWallpaper(_wallpaper)],
      );

      await resolved.release();

      expect(previews.released, hasLength(1));
    });

    test('carries the purity the source published', () async {
      // Per-file, so a mixed browse selection beams its safe wallpapers and is
      // refused for its explicit ones — see BeamWallpapers.
      final ResolvedBeamFiles resolved = await ResolveBeamFiles(
        FakeLocalPreviewCache(),
      ).call(<BeamCandidate>[BeamCandidate.ofWallpaper(_wallpaper)]);

      expect(resolved.files.single.purity, Purity.sfw);
    });
  });

  group('the name the receiver writes it under', () {
    test("is the wallpaper's own name, not the cache copy's", () async {
      // Shipped wrong once and caught on hardware: the name came from the
      // resolved path, which for anything behind SAF or MediaStore is a cache
      // copy called `preview-221123410085484` with no extension at all. A real
      // 11MB transfer landed on the desktop under exactly that.
      final ResolvedBeamFiles resolved = await ResolveBeamFiles(
        FakeLocalPreviewCache(),
      ).call(_private(<PrivateImage>[_image('aaaaaa', location: _appPrivate)]));

      expect(resolved.files.single.fileName, 'wallhaven-aaaaaa.jpg');
      expect(resolved.files.single.path, startsWith('/cache/preview-'));
    });

    test('keeps the real extension out of a SAF document id', () async {
      // A vault URI hides the name inside a percent-encoded document id, and
      // the vault's own hidden folder is literally called `.tela` — a dot that
      // must not become the extension.
      final ResolvedBeamFiles resolved =
          await ResolveBeamFiles(
            FakeLocalPreviewCache(),
          ).call(
            _private(<PrivateImage>[
              _image(
                'bbbbbb',
                location: Uri.parse(
                  'content://com.android.externalstorage.documents/document/'
                  'primary%3APictures%2FTela%2F.tela%2Fwallhaven-bbbbbb.png',
                ),
                tier: StorageTier.filesOutsideGallery,
              ),
            ]),
          );

      expect(resolved.files.single.fileName, 'wallhaven-bbbbbb.png');
      expect(resolved.files.single.mimeType, 'image/png');
    });

    test('an unreadable extension is left off, never guessed', () async {
      // The same judgement `wallpaperFileName` makes: an extensionless name
      // beats a wrong one.
      final ResolvedBeamFiles resolved =
          await ResolveBeamFiles(
            FakeLocalPreviewCache(),
          ).call(
            _private(<PrivateImage>[
              _image(
                'cccccc',
                location: Uri.parse('content://provider/doc/17'),
              ),
            ]),
          );

      expect(resolved.files.single.fileName, 'wallhaven-cccccc');
    });
  });

  group('the private library is explicit at both of its homes', () {
    test('an app-private image is explicit', () async {
      final ResolvedBeamFiles resolved = await ResolveBeamFiles(
        FakeLocalPreviewCache(),
      ).call(_private(<PrivateImage>[_image('aaaaaa', location: _appPrivate)]));

      expect(resolved.files.single.purity, Purity.nsfw);
    });

    test('a vault image is explicit too — regression', () async {
      // Shipped wrong once: purity was read off the tier, which marked every
      // vault image safe. The vault is the private library's *other disk* —
      // where explicit downloads land once the destination points at a card —
      // not a safer tier, so that would have beamed explicit files straight
      // past the opt-in gate.
      final ResolvedBeamFiles resolved =
          await ResolveBeamFiles(
            FakeLocalPreviewCache(),
          ).call(
            _private(<PrivateImage>[
              _image(
                'aaaaaa',
                location: _vault,
                tier: StorageTier.filesOutsideGallery,
              ),
            ]),
          );

      expect(resolved.files.single.purity, Purity.nsfw);
    });
  });

  group('the throwaway copies', () {
    test('releases every temporary preview it made', () async {
      // materialize copies the whole original for a SAF source; a batch of
      // forty left unreleased is forty duplicated wallpapers in the cache.
      final FakeLocalPreviewCache previews = FakeLocalPreviewCache();
      final ResolvedBeamFiles resolved = await ResolveBeamFiles(previews).call(
        _private(<PrivateImage>[_image('aaaaaa', location: _vault)]),
      );

      await resolved.release();

      expect(previews.released, hasLength(1));
    });

    test('never releases a file the user actually downloaded', () async {
      // An app-private path is the download's own file, not a copy. Releasing
      // it would delete the wallpaper.
      final FakeLocalPreviewCache previews = FakeLocalPreviewCache();
      final ResolvedBeamFiles resolved = await ResolveBeamFiles(previews).call(
        _private(<PrivateImage>[_image('aaaaaa', location: _appPrivate)]),
      );

      await resolved.release();

      expect(previews.released, isEmpty);
    });

    test('is safe to release twice', () async {
      final FakeLocalPreviewCache previews = FakeLocalPreviewCache();
      final ResolvedBeamFiles resolved = await ResolveBeamFiles(previews).call(
        _private(<PrivateImage>[_image('aaaaaa', location: _vault)]),
      );

      await resolved.release();
      await resolved.release();

      expect(previews.released, hasLength(1));
    });
  });
}
