import 'package:tela/domain/models/external_link_failure.dart';
import 'package:tela/domain/ports/external_link.dart';
import 'package:url_launcher/url_launcher.dart';

/// [ExternalLink] over the `url_launcher` plugin.
///
/// Opens in an external browser deliberately — [LaunchMode.externalApplication]
/// — rather than an in-app tab tela would have to keep alive; the hand-off is
/// the whole point. A refusal or a plugin error becomes an
/// [ExternalLinkFailure] so the vendor exception never reaches a feature.
class UrlLauncherExternalLink implements ExternalLink {
  /// Creates the adapter.
  const UrlLauncherExternalLink();

  @override
  Future<void> open(Uri url) async {
    try {
      final bool launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const ExternalLinkFailure(ExternalLinkProblem.unavailable);
      }
    } on ExternalLinkFailure {
      rethrow;
    } on Object {
      throw const ExternalLinkFailure(ExternalLinkProblem.unknown);
    }
  }
}
