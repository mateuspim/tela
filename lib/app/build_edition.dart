/// The product edition compiled into this binary.
///
/// Release commands must pass `--dart-define=TELA_EDITION=<name>`. The default
/// remains [full] so local development and existing installs keep today's
/// behaviour when no define is supplied.
enum BuildEdition {
  /// Google Play edition: Wallhaven without credentials or explicit content.
  play,

  /// Wallhaven-only edition with optional credentials and explicit content.
  wallhaven,

  /// Clean multi-source edition: Wallhaven plus server-filtered konachan.net.
  safe,

  /// Every source and feature, including unrestricted Konachan.
  full;

  /// Parses the value supplied by release automation.
  static BuildEdition parse(String raw) {
    return switch (raw) {
      'play' => BuildEdition.play,
      'wallhaven' => BuildEdition.wallhaven,
      'safe' => BuildEdition.safe,
      'full' => BuildEdition.full,
      _ => throw ArgumentError(
        'TELA_EDITION must be play|wallhaven|safe|full, got "$raw"',
      ),
    };
  }

  /// Whether a Wallhaven API key can be stored and used.
  bool get allowsWallhavenCredentials =>
      this == BuildEdition.wallhaven || this == BuildEdition.full;

  /// Whether Konachan is registered as a browse source.
  bool get includesKonachan =>
      this == BuildEdition.safe || this == BuildEdition.full;

  /// Whether requests may reach unrestricted konachan.com.
  bool get allowsUnrestrictedKonachan => this == BuildEdition.full;

  /// Whether explicit purity and the private-content surfaces are present.
  bool get allowsExplicitContent =>
      this == BuildEdition.wallhaven || this == BuildEdition.full;

  /// Stable release artifact stem.
  String get artifactName => switch (this) {
    BuildEdition.play => 'tela-play',
    BuildEdition.wallhaven => 'tela-wallhaven',
    BuildEdition.safe => 'tela-safe',
    BuildEdition.full => 'tela-full',
  };
}

const String _buildEditionName = String.fromEnvironment(
  'TELA_EDITION',
  defaultValue: 'full',
);

/// The edition selected at compile time.
///
/// This is a const expression so release tree shaking can remove adapters and
/// screens that an edition can never reach.
const BuildEdition buildEdition = _buildEditionName == 'play'
    ? BuildEdition.play
    : _buildEditionName == 'wallhaven'
    ? BuildEdition.wallhaven
    : _buildEditionName == 'safe'
    ? BuildEdition.safe
    : BuildEdition.full;
