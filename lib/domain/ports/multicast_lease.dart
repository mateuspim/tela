/// Keeps the device able to *receive* multicast while it is held.
///
/// A platform capability behind a project-owned interface, like every other
/// one here (CLAUDE.md, dependency rule). Android's Wi-Fi stack drops
/// multicast not addressed to the device, so without a lock beam discovery
/// joins its group, opens its socket, and receives nothing — with no error
/// anywhere to notice.
///
/// Balanced: every [acquire] owes a [release]. The implementation counts
/// holders, so overlapping discoveries do not blind each other.
///
/// ```dart
/// await lease.acquire();
/// try { await for (final t in beam.discover()) show(t); }
/// finally { await lease.release(); }
/// ```
abstract interface class MulticastLease {
  /// Takes the lock, answering whether the device had one to give.
  ///
  /// False is not a failure: a device with no Wi-Fi service (cellular only, a
  /// bare emulator) simply has no multicast to receive, and the hand-typed
  /// address is the path that still works there.
  Future<bool> acquire();

  /// Gives one holder's claim back.
  Future<void> release();
}
