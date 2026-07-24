/// Decodes one of tela's fixed-width bit masks back into the enum values it
/// selects — the inverse of `CategoryFilter.encodeStored`.
///
/// This is the shape tela's *own* settings rows are written in. It coincides
/// with Wallhaven's `categories` param, which is where it came from, but the
/// two are no longer the same contract: the wire encoding lives in
/// `data/wallhaven/`, and a row on disk must keep reading the same forever
/// whatever any source's API does next.
///
/// Returns null for anything that is not a mask over [values]: the wrong width,
/// a character that is not `0` or `1`, or a mask that selects nothing. Null
/// rather than a throw because the callers read *stored* values, and a corrupt
/// row must cost a setting, not the app.
///
/// ```dart
/// decodeStoredBits('110', Purity.values); // {Purity.sfw, Purity.sketchy}
/// ```
Set<T>? decodeStoredBits<T extends Enum>(String bits, List<T> values) {
  if (bits.length != values.length) return null;

  final Set<T> selected = <T>{};
  for (int i = 0; i < bits.length; i++) {
    if (bits[i] == '1') selected.add(values[i]);
    if (bits[i] != '0' && bits[i] != '1') return null;
  }
  return selected.isEmpty ? null : selected;
}

/// Encodes [selected] as a fixed-width mask over [values].
///
/// Refuses an empty selection: "nothing" is not a filter tela can store and
/// read back as anything meaningful, and every caller has a non-empty set.
String encodeStoredBits<T extends Enum>(List<T> values, Set<T> selected) {
  final String bits = values
      .map((T value) => selected.contains(value) ? '1' : '0')
      .join();
  if (!bits.contains('1')) {
    throw ArgumentError(
      'a stored filter must select at least one value, '
      'got none of ${values.map((T v) => v.name).join('|')}',
    );
  }
  return bits;
}
