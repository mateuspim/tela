import 'dart:math';

import 'package:tela/data/localsend/localsend_wire.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// Produces this install's LocalSend identity, generating it once.
///
/// The fingerprint is kept because the protocol identifies a *device* by it: a
/// receiver that has accepted this phone before recognises it again, where a
/// fresh string every launch would read as a new, unknown sender each time.
///
/// Generated with `Random.secure` rather than a package — a random opaque
/// string is the entire specification for an `http` fingerprint, so pulling in
/// a UUID dependency for it would buy nothing (CLAUDE.md: wrap what you must,
/// add what you need).
class BeamIdentityStore {
  /// Creates the store over the settings port the fingerprint lives in.
  const BeamIdentityStore(this._settings, {Random? random}) : _random = random;

  final SettingsRepository _settings;
  final Random? _random;

  /// How many bytes of randomness the fingerprint carries.
  ///
  /// 32 hex characters. The spec asks only for "a random string"; this is the
  /// same width a UUID would have given, without the dependency.
  static const int _byteCount = 16;

  /// This install's identity, generating and persisting one on first use.
  Future<LocalSendIdentity> identity() async {
    final String? stored = await _settings.loadBeamFingerprint();
    if (stored != null) {
      return LocalSendIdentity(alias: _alias, fingerprint: stored);
    }
    final String generated = _generate();
    await _settings.saveBeamFingerprint(generated);
    return LocalSendIdentity(alias: _alias, fingerprint: generated);
  }

  /// What a receiver shows in its "accept?" prompt.
  ///
  /// The app's name, not the device's: reading the phone's own name would need
  /// a plugin, and "tela" is what makes the prompt recognisable to the one
  /// person who ever sees it.
  static const String _alias = 'tela';

  String _generate() {
    final Random random = _random ?? Random.secure();
    return <String>[
      for (int i = 0; i < _byteCount; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}
