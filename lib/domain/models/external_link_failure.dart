/// Why tela could not hand a URL to the device's browser.
enum ExternalLinkProblem {
  /// Nothing on the device offered to open the URL — no browser, or a scheme
  /// the platform will not launch.
  unavailable,

  /// The platform returned a failure tela does not recognize yet.
  unknown,
}

/// A safe, domain-owned failure for opening an external link.
///
/// Carries only the [problem], never the URL or the vendor message, so a source
/// address the user tapped cannot leak through logs or UI by accident — the
/// same discipline the share and apply failures keep.
class ExternalLinkFailure implements Exception {
  /// Creates a failure describing [problem].
  const ExternalLinkFailure(this.problem);

  /// The actionable category of the failure.
  final ExternalLinkProblem problem;

  @override
  String toString() => 'ExternalLinkFailure(${problem.name})';
}
