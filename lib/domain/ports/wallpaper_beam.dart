import 'package:tela/domain/models/beam_failure.dart';
import 'package:tela/domain/models/beam_file.dart';
import 'package:tela/domain/models/beam_target.dart';

/// Sends wallpaper files to another machine on the local network.
///
/// The port behind tela's LocalSend support, owned by the domain and
/// implemented once in `data/localsend/`. Features depend on this and never on
/// Dio or `dart:io`, so the protocol could be swapped for another by writing
/// one adapter (CLAUDE.md, dependency rule).
///
/// **tela is a sender only, and the protocol allows that** — LocalSend needs
/// just one party to run an HTTP server, and that party is the receiver. So
/// there is no inbound port here, no listening socket to leave open, and
/// nothing for a hostile device on the same network to reach.
///
/// ```dart
/// final BeamTarget target = await beam.discover().first;
/// await beam.send(target: target, files: files, onProgress: report);
/// ```
abstract interface class WallpaperBeam {
  /// Announces tela and yields every receiver that answers, until cancelled.
  ///
  /// A long-lived stream rather than a list, because discovery is not a
  /// request-response: receivers answer at their own pace and new ones appear
  /// as they are switched on, so a chooser wants to grow its list rather than
  /// wait out a fixed timeout and then show a stale one.
  ///
  /// Yields each target once, keyed on [BeamTarget.fingerprint], so a receiver
  /// that re-announces on its own schedule does not appear twice.
  ///
  /// Never throws for a network that carries no multicast — it simply yields
  /// nothing, because a silent network and an empty one are the same
  /// observation, and [sendTo] exists for exactly that case.
  Stream<BeamTarget> discover();

  /// Confirms one machine at [host]:[port] is a receiver, for when discovery
  /// finds nothing.
  ///
  /// Multicast does not survive every network — a guest VLAN, an AP with
  /// client isolation, a router filtering `224.0.0.0/24` — and on those the
  /// address typed by hand is the only way through. Answers the target's own
  /// self-description so the chooser can show the alias it reports rather than
  /// the bare address that was typed.
  ///
  /// Throws [BeamUnreachableFailure] when nothing answers there.
  Future<BeamTarget> sendTo({required String host, required int port});

  /// Sends every file in [files] to [target], reporting bytes as they go.
  ///
  /// [onProgress] is called with the total bytes sent so far across the whole
  /// batch, not per file — it feeds one progress bar, and a per-file callback
  /// would make the caller do the summing.
  ///
  /// Throws [BeamDeclinedFailure] when the receiver refuses, [BeamBusyFailure]
  /// when it is mid-transfer, [BeamPinRequiredFailure] when it wants a PIN,
  /// and [BeamUnreachableFailure] when it stops answering partway.
  Future<void> send({
    required BeamTarget target,
    required List<BeamFile> files,
    void Function(int bytesSent)? onProgress,
    String? pin,
  });
}
