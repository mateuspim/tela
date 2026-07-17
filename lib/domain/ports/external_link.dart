import 'package:tela/domain/models/external_link_failure.dart';

/// Opens a URL outside tela, in the device's browser.
///
/// The port behind "View on Wallhaven" and a wallpaper's credited source: tela
/// hands off the address and steps out of the way, rather than embedding a
/// web view it would have to own. Wraps the `url_launcher` plugin so a feature
/// never imports it directly (CLAUDE.md's ports rule).
///
/// ```dart
/// await ref.read(externalLinkProvider).open(wallpaper.pageUrl);
/// ```
abstract interface class ExternalLink {
  /// Opens [url] in an external application, typically a browser.
  ///
  /// Throws [ExternalLinkFailure] when the device can open nothing for it, so
  /// the caller can say so rather than failing silently.
  Future<void> open(Uri url);
}
