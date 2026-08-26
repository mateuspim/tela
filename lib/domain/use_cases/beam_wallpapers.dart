import 'package:tela/domain/models/beam_failure.dart';
import 'package:tela/domain/models/beam_file.dart';
import 'package:tela/domain/models/beam_target.dart';
import 'package:tela/domain/models/bitmap_export_rule.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/ports/multicast_lease.dart';
import 'package:tela/domain/ports/settings_repository.dart';
import 'package:tela/domain/ports/wallpaper_beam.dart';

/// Sends wallpapers to a machine on the local network, under the beam gate.
///
/// **The one place explicit pixels are allowed to leave the device, and the
/// only place that decides it.** `mayBeamBitmap` states the rule; this reads
/// the stored setting and applies it, so the UI cannot beam explicit content
/// by forgetting to ask, and a future caller gets the gate for free.
///
/// Enforced twice, the way every NSFW rule in tela is: here, and again in the
/// UI that withholds the action. The refusal is [BeamExplicitRefusedFailure],
/// raised **before any byte leaves**, and it names the setting rather than
/// reading as a malfunction.
///
/// ```dart
/// await beamWallpapers(target: target, files: files);
/// ```
class BeamWallpapers {
  /// Creates the use case. Every collaborator is injected (CLAUDE.md: no
  /// global singletons).
  const BeamWallpapers({
    required WallpaperBeam beam,
    required SettingsRepository settings,
    required MulticastLease lease,
  }) : _beam = beam,
       _settings = settings,
       _lease = lease;

  final WallpaperBeam _beam;
  final SettingsRepository _settings;
  final MulticastLease _lease;

  /// Every receiver that answers, as it answers.
  ///
  /// Holds the multicast lock for exactly as long as someone is listening.
  /// Without it Android drops the announcements and this yields nothing
  /// forever; held beyond the chooser it costs battery for nothing, so it is
  /// tied to the subscription rather than to the app.
  Stream<BeamTarget> discover() async* {
    await _lease.acquire();
    try {
      yield* _beam.discover();
    } finally {
      await _lease.release();
    }
  }

  /// Confirms a hand-typed address is a receiver. See [WallpaperBeam.sendTo].
  Future<BeamTarget> targetAt({required String host, required int port}) =>
      _beam.sendTo(host: host, port: port);

  /// Sends [files] to [target], refusing explicit ones unless allowed.
  ///
  /// **All-or-nothing on the gate, deliberately.** A batch holding one
  /// explicit wallpaper is refused whole rather than quietly sent minus that
  /// file: silently dropping one of forty is a transfer the user believes
  /// completed, and they would find out by its absence on the desktop much
  /// later. The caller filters first if it wants a partial send.
  Future<void> call({
    required BeamTarget target,
    required List<BeamFile> files,
    void Function(int bytesSent)? onProgress,
    String? pin,
  }) async {
    await _guardExplicit(files);
    return _beam.send(
      target: target,
      files: files,
      onProgress: onProgress,
      pin: pin,
    );
  }

  /// Whether explicit wallpapers may currently be beamed.
  ///
  /// Read by the UI to *withhold* the action, which is the second of the two
  /// enforcements. A screen asking this is not trusted to have asked — [call]
  /// checks again regardless.
  Future<bool> get allowsExplicit => _settings.loadExplicitBeamAllowed();

  Future<void> _guardExplicit(List<BeamFile> files) async {
    final bool hasExplicit = files.any(
      (BeamFile file) => file.purity == Purity.nsfw,
    );
    if (!hasExplicit) return;
    final bool allowed = await _settings.loadExplicitBeamAllowed();
    if (mayBeamBitmap(Purity.nsfw, explicitBeamEnabled: allowed)) return;
    throw const BeamExplicitRefusedFailure();
  }
}
