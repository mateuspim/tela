import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/beam_failure.dart';
import 'package:tela/domain/models/beam_file.dart';
import 'package:tela/domain/models/beam_target.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/use_cases/beam_wallpapers.dart';

import '../../fakes/fake_multicast_lease.dart';
import '../../fakes/fake_settings_repository.dart';
import '../../fakes/fake_wallpaper_beam.dart';

const BeamTarget _desktop = BeamTarget(
  alias: 'workstation',
  host: '192.168.50.20',
  port: 53317,
  fingerprint: 'receiver-fp',
  usesHttps: false,
);

BeamFile _file(String id, Purity purity) => BeamFile(
  id: id,
  fileName: '$id.jpg',
  path: '/tmp/$id.jpg',
  sizeBytes: 10,
  mimeType: 'image/jpeg',
  purity: purity,
);

({BeamWallpapers use, FakeWallpaperBeam beam}) _wired({
  bool explicitAllowed = false,
}) {
  final FakeWallpaperBeam beam = FakeWallpaperBeam();
  return (
    use: BeamWallpapers(
      beam: beam,
      settings: FakeSettingsRepository()..explicitBeamAllowed = explicitAllowed,
      lease: FakeMulticastLease(),
    ),
    beam: beam,
  );
}

void main() {
  group('safe and sketchy content beams freely', () {
    test('sends a safe batch', () async {
      final ({BeamWallpapers use, FakeWallpaperBeam beam}) wired = _wired();

      await wired.use(
        target: _desktop,
        files: <BeamFile>[_file('one', Purity.sfw)],
      );

      expect(wired.beam.sent, hasLength(1));
    });

    test('sketchy is not explicit, matching every other rule here', () async {
      final ({BeamWallpapers use, FakeWallpaperBeam beam}) wired = _wired();

      await wired.use(
        target: _desktop,
        files: <BeamFile>[_file('one', Purity.sketchy)],
      );

      expect(wired.beam.sent, hasLength(1));
    });
  });

  group('discovery holds the multicast lock', () {
    test('takes it while listening and gives it back at the end', () async {
      // Without the lock Android drops the very packets discovery listens for,
      // so this yields nothing forever with no error to notice. Held past the
      // chooser it costs battery for nothing.
      final FakeMulticastLease lease = FakeMulticastLease();
      final BeamWallpapers use = BeamWallpapers(
        beam: FakeWallpaperBeam(targets: <BeamTarget>[_desktop]),
        settings: FakeSettingsRepository(),
        lease: lease,
      );

      await use.discover().toList();

      expect(lease.acquires, 1);
      expect(lease.isBalanced, isTrue);
    });

    test('gives it back when the listener leaves early', () async {
      final FakeMulticastLease lease = FakeMulticastLease();
      final BeamWallpapers use = BeamWallpapers(
        beam: FakeWallpaperBeam(targets: <BeamTarget>[_desktop]),
        settings: FakeSettingsRepository(),
        lease: lease,
      );

      // A chooser closed on the first result, which is the ordinary case.
      await use.discover().first;

      expect(lease.isBalanced, isTrue);
    });

    test('still lists nothing rather than failing without the lock', () async {
      // A cellular-only device has no multicast to receive. That is not an
      // error worth raising — the hand-typed address still works.
      final BeamWallpapers use = BeamWallpapers(
        beam: FakeWallpaperBeam(),
        settings: FakeSettingsRepository(),
        lease: FakeMulticastLease(granted: false),
      );

      expect(await use.discover().toList(), isEmpty);
    });
  });

  group('the explicit gate', () {
    test('refuses explicit content while the setting is off', () async {
      final ({BeamWallpapers use, FakeWallpaperBeam beam}) wired = _wired();

      await expectLater(
        wired.use(
          target: _desktop,
          files: <BeamFile>[_file('one', Purity.nsfw)],
        ),
        throwsA(isA<BeamExplicitRefusedFailure>()),
      );
      // The whole point: refused *before any byte leaves*, not mid-transfer.
      expect(wired.beam.sent, isEmpty);
    });

    test('allows explicit content once the setting is on', () async {
      final ({BeamWallpapers use, FakeWallpaperBeam beam}) wired = _wired(
        explicitAllowed: true,
      );

      await wired.use(
        target: _desktop,
        files: <BeamFile>[_file('one', Purity.nsfw)],
      );

      expect(wired.beam.sent, hasLength(1));
    });

    test(
      'refuses a mixed batch whole, rather than dropping one file',
      () async {
        // Silently sending 39 of 40 is a transfer the user believes completed,
        // and they would find out by its absence on the desktop much later.
        final ({BeamWallpapers use, FakeWallpaperBeam beam}) wired = _wired();

        await expectLater(
          wired.use(
            target: _desktop,
            files: <BeamFile>[
              _file('safe', Purity.sfw),
              _file('explicit', Purity.nsfw),
            ],
          ),
          throwsA(isA<BeamExplicitRefusedFailure>()),
        );
        expect(wired.beam.sent, isEmpty);
      },
    );

    test('reports what the UI should withhold', () async {
      expect(await _wired().use.allowsExplicit, isFalse);
      expect(
        await _wired(explicitAllowed: true).use.allowsExplicit,
        isTrue,
      );
    });

    test('re-reads the setting per send, not once at construction', () async {
      // A user turning the gate off in Settings must not leave a use case
      // built earlier still willing to send.
      final FakeWallpaperBeam beam = FakeWallpaperBeam();
      final FakeSettingsRepository settings = FakeSettingsRepository()
        ..explicitBeamAllowed = true;
      final BeamWallpapers use = BeamWallpapers(
        beam: beam,
        settings: settings,
        lease: FakeMulticastLease(),
      );

      await use(
        target: _desktop,
        files: <BeamFile>[_file('one', Purity.nsfw)],
      );
      settings.explicitBeamAllowed = false;

      await expectLater(
        use(target: _desktop, files: <BeamFile>[_file('two', Purity.nsfw)]),
        throwsA(isA<BeamExplicitRefusedFailure>()),
      );
      expect(wiredSentIds(beam), <String>['one']);
    });
  });
}

/// The ids actually handed to the port, flattened across sends.
List<String> wiredSentIds(FakeWallpaperBeam beam) => <String>[
  for (final List<BeamFile> batch in beam.sent)
    for (final BeamFile file in batch) file.id,
];
