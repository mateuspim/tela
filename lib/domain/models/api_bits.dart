/// Decodes one of Wallhaven's fixed-width bit masks back into the enum values
/// it selects — the inverse of `CategoryFilter.toApiBits` and
/// `PurityFilter.toApiBits`.
///
/// Returns null for anything that is not a mask over [values]: the wrong width,
/// a character that is not `0` or `1`, or a mask that selects nothing (which
/// the encoders refuse to produce, because Wallhaven answers `"000"` with a
/// 400). Null rather than a throw because the callers read *stored* values, and
/// a corrupt row must cost a setting, not the app.
///
/// ```dart
/// decodeApiBits('110', Purity.values); // {Purity.sfw, Purity.sketchy}
/// ```
Set<T>? decodeApiBits<T extends Enum>(String bits, List<T> values) {
  if (bits.length != values.length) return null;

  final Set<T> selected = <T>{};
  for (int i = 0; i < bits.length; i++) {
    if (bits[i] == '1') selected.add(values[i]);
    if (bits[i] != '0' && bits[i] != '1') return null;
  }
  return selected.isEmpty ? null : selected;
}
