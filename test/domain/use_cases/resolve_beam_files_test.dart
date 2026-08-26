import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
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
