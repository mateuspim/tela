import 'package:tela/domain/models/search_query.dart';

/// The aspect ratios a listing asks for, as the three choices worth offering on
/// a phone.
///
/// Wallhaven takes an open-ended ratio list, but "portrait / landscape / any" is
/// the only cut of it a wallpaper app needs. Named for the ratios it sets, not
/// `Orientation`, which is already a Flutter enum — and every file with the
/// filter sheet in it imports Material.
///
/// ```dart
/// RatioChoice.of(query).ratios; // <String>['9x16']
/// ```
enum RatioChoice {
  /// Phone-shaped. The default, because this is a phone.
  portrait(<String>['9x16']),

  /// Desktop-shaped, for downloading to sync elsewhere.
  landscape(<String>['16x9']),

  /// No ratio filter at all.
  any(<String>[]);

  const RatioChoice(this.ratios);

  /// The `ratios` param value this choice stands for.
  final List<String> ratios;

  /// The choice [query] currently expresses.
  ///
  /// Falls back to [any] for a ratio set we never offered: nothing in the app
  /// builds one today, but [SearchQuery] permits it and this must not throw.
  static RatioChoice of(SearchQuery query) {
    return RatioChoice.values.firstWhere(
      (RatioChoice choice) => _sameRatios(choice.ratios, query.ratios),
      orElse: () => RatioChoice.any,
    );
  }

  static bool _sameRatios(List<String> a, List<String> b) {
    return a.length == b.length && a.toSet().containsAll(b);
  }
}
