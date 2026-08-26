import 'package:tela/domain/models/beam_failure.dart';
import 'package:tela/domain/models/beam_file.dart';
import 'package:tela/domain/models/beam_target.dart';
import 'package:tela/domain/ports/wallpaper_beam.dart';

/// In-memory [WallpaperBeam] that records what it was asked to send.
///
/// Records whole batches rather than flattening them, so a test can assert
/// that a refused batch left *nothing* — the difference between refusing and
/// partially sending is the thing the explicit gate exists to guarantee.
class FakeWallpaperBeam implements WallpaperBeam {
  /// Creates a fake that accepts everything, or throws [failure].
  FakeWallpaperBeam({this.targets = const <BeamTarget>[], this.failure});

  /// What [discover] yields.
  final List<BeamTarget> targets;

  /// Thrown by [send] and [sendTo] when set.
  final BeamFailure? failure;

  /// Every batch handed to [send], in order.
  final List<List<BeamFile>> sent = <List<BeamFile>>[];

  @override
  Stream<BeamTarget> discover() => Stream<BeamTarget>.fromIterable(targets);

  @override
  Future<BeamTarget> sendTo({required String host, required int port}) async {
    final BeamFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    return targets.isNotEmpty
        ? targets.first
        : BeamTarget(
            alias: host,
            host: host,
            port: port,
            fingerprint: '$host:$port',
            usesHttps: false,
          );
  }

  @override
  Future<void> send({
    required BeamTarget target,
    required List<BeamFile> files,
    void Function(int bytesSent)? onProgress,
    String? pin,
  }) async {
    final BeamFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    sent.add(files);
    onProgress?.call(
      files.fold<int>(0, (int total, BeamFile file) => total + file.sizeBytes),
    );
  }
}
