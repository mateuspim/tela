import 'package:tela/domain/ports/multicast_lease.dart';

/// In-memory [MulticastLease] that records how it was balanced.
///
/// The counts are the point: a discovery that takes the lock and never gives
/// it back costs battery for the life of the app, and one that gives it back
/// early goes deaf partway through.
class FakeMulticastLease implements MulticastLease {
  /// Creates a lease that grants unless [granted] says otherwise.
  FakeMulticastLease({this.granted = true});

  /// What [acquire] answers — false stands in for a device with no Wi-Fi.
  final bool granted;

  /// How many times the lock was taken.
  int acquires = 0;

  /// How many times it was given back.
  int releases = 0;

  /// Whether every acquire has been balanced by a release.
  bool get isBalanced => acquires == releases;

  @override
  Future<bool> acquire() async {
    acquires++;
    return granted;
  }

  @override
  Future<void> release() async {
    releases++;
  }
}
