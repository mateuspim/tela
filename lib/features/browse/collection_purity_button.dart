import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_taxonomy_text.dart';
import 'package:tela/domain/models/purity.dart';

/// The purity control a collection listing gets *instead of* the filter sheet.
///
/// Its own control rather than a narrowed `BrowseFilterButton` because the
/// constraint is not a preference: a collection's contents endpoint honours
/// `purity` and silently ignores every other filter (measured live against
/// Wallhaven 2026-08-26). Offering the full sheet here would draw categories,
/// ratios, resolutions and sortings that do nothing at all when touched.
///
/// ```dart
/// CollectionPurityButton(purity: purity, onChanged: apply);
/// ```
class CollectionPurityButton extends StatelessWidget {
  /// Creates the control over [purity], reporting edits to [onChanged].
  const CollectionPurityButton({
    required this.purity,
    required this.onChanged,
    super.key,
  });

  /// The purities currently shown.
  final PurityFilter purity;

  /// Called with the new selection. Never called with an empty one.
  final ValueChanged<PurityFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return PopupMenuButton<Purity>(
      icon: const Icon(Icons.visibility_outlined),
      tooltip: l10n.filterPurity,
      onSelected: _toggle,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<Purity>>[
        for (final Purity value in Purity.values)
          CheckedPopupMenuItem<Purity>(
            value: value,
            checked: purity.purities.contains(value),
            child: Text(purityLabel(l10n, value)),
          ),
      ],
    );
  }

  /// Flips one purity, refusing to empty the set.
  ///
  /// The same rule the filter sheet enforces (`filterPurityRequired`): a
  /// listing with no purity selected is not a narrower listing, it is a
  /// guaranteed empty one, and Wallhaven answers the `"000"` mask with a 400.
  void _toggle(Purity value) {
    final Set<Purity> next = <Purity>{...purity.purities};
    if (!next.remove(value)) next.add(value);
    if (next.isEmpty) return;
    onChanged(PurityFilter(next));
  }
}
