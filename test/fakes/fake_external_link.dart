import 'package:tela/domain/models/external_link_failure.dart';
import 'package:tela/domain/ports/external_link.dart';

/// A [ExternalLink] that records the URLs it was asked to open, and can be told
/// to fail as a device with no browser would.
class FakeExternalLink implements ExternalLink {
  /// Creates a fake that succeeds, or fails with [failure] when one is given.
  FakeExternalLink({this.failure});

  /// The failure to throw instead of opening, or null to succeed.
  final ExternalLinkFailure? failure;

  /// Every URL [open] was called with, in order.
  final List<Uri> opened = <Uri>[];

  @override
  Future<void> open(Uri url) async {
    opened.add(url);
    if (failure != null) throw failure!;
  }
}
