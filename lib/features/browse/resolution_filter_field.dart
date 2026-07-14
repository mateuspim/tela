import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/browse_filter_text.dart';
import 'package:tela/core/ui/screen_resolution.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/resolution_filter.dart';

/// The three modes the resolution filter can be in.
///
/// A mode rather than three independent controls, because Wallhaven's two size
/// params *conflict*: sending `atleast` and `resolutions` together honours the
/// first and silently ignores the second. See [ResolutionFilter].
enum _Mode { automatic, atLeast, exactly }

/// Edits a [ResolutionFilter] as a mode plus the sizes that mode needs.
///
/// Its own widget rather than another method on the filter sheet: it is the
/// only filter with a mode *and* a size list *and* a custom-value dialog behind
/// it, and the sheet is already the longest file in the feature.
class ResolutionFilterField extends StatelessWidget {
  /// Creates the field, showing [value] and reporting edits via [onChanged].
  const ResolutionFilterField({
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// The filter as it currently stands.
  final ResolutionFilter value;

  /// Called with the filter the user just built.
  final ValueChanged<ResolutionFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Resolution screen = screenResolution(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _modes(l10n, screen),
        const SizedBox(height: 12),
        _body(context, l10n, screen),
      ],
    );
  }

  Widget _modes(AppLocalizations l10n, Resolution screen) {
    return SegmentedButton<_Mode>(
      segments: <ButtonSegment<_Mode>>[
        for (final _Mode mode in _Mode.values)
          ButtonSegment<_Mode>(
            value: mode,
            label: Text(_modeLabel(l10n, mode)),
          ),
      ],
      selected: <_Mode>{_modeOf(value)},
      onSelectionChanged: (Set<_Mode> chosen) =>
          onChanged(_seedFor(chosen.single, screen)),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n, Resolution screen) {
    return switch (value) {
      AutomaticResolution() => _hint(
        context,
        l10n.resolutionAutomaticHint('${screen.width}', '${screen.height}'),
      ),
      final AtLeastResolution filter => _AtLeastSizes(
        screen: screen,
        selected: filter.minimum,
        onChanged: (Resolution size) => onChanged(AtLeastResolution(size)),
      ),
      final ExactResolutions filter => _ExactSizes(
        screen: screen,
        selected: filter.sizes,
        onChanged: _onExactChanged,
      ),
    };
  }

  /// An exact filter with no sizes left asks for nothing at all, so emptying
  /// the last chip falls back to Automatic rather than a listing of nothing.
  void _onExactChanged(List<Resolution> sizes) {
    if (sizes.isEmpty) {
      onChanged(const AutomaticResolution());
      return;
    }
    onChanged(ExactResolutions(sizes));
  }

  Widget _hint(BuildContext context, String text) {
    final ThemeData theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  static String _modeLabel(AppLocalizations l10n, _Mode mode) {
    return switch (mode) {
      _Mode.automatic => l10n.resolutionAutomatic,
      _Mode.atLeast => l10n.resolutionAtLeast,
      _Mode.exactly => l10n.resolutionExactly,
    };
  }

  static _Mode _modeOf(ResolutionFilter filter) {
    return switch (filter) {
      AutomaticResolution() => _Mode.automatic,
      AtLeastResolution() => _Mode.atLeast,
      ExactResolutions() => _Mode.exactly,
    };
  }

  /// The filter a freshly picked mode starts on.
  ///
  /// Both picked modes need a size before they mean anything, and the honest
  /// seed is the screen: it is what Automatic was already asking for. So
  /// switching mode changes what the user *can* edit without changing the
  /// listing under them — and the size they most likely want is pre-selected.
  static ResolutionFilter _seedFor(_Mode mode, Resolution screen) {
    return switch (mode) {
      _Mode.automatic => const AutomaticResolution(),
      _Mode.atLeast => AtLeastResolution(screen),
      _Mode.exactly => ExactResolutions(<Resolution>[screen]),
    };
  }
}

/// The `atleast` sizes, as a radio: a listing has one minimum.
class _AtLeastSizes extends StatelessWidget {
  const _AtLeastSizes({
    required this.screen,
    required this.selected,
    required this.onChanged,
  });

  final Resolution screen;
  final Resolution selected;
  final ValueChanged<Resolution> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return _SizeGroups(
      screen: screen,
      isSelected: (Resolution size) => size == selected,
      onTap: onChanged,
      custom: () => _askForSize(context, l10n, onChanged),
    );
  }
}

/// The `resolutions` sizes, as chips: the param is a union.
class _ExactSizes extends StatelessWidget {
  const _ExactSizes({
    required this.screen,
    required this.selected,
    required this.onChanged,
  });

  final Resolution screen;
  final List<Resolution> selected;
  final ValueChanged<List<Resolution>> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.resolutionExactlyHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _SizeGroups(
          screen: screen,
          isSelected: selected.contains,
          onTap: _toggle,
          custom: () => _askForSize(context, l10n, _add),
        ),
      ],
    );
  }

  void _toggle(Resolution size) {
    final List<Resolution> next = <Resolution>[...selected];
    if (!next.remove(size)) next.add(size);
    onChanged(next);
  }

  void _add(Resolution size) {
    if (selected.contains(size)) return;
    onChanged(<Resolution>[...selected, size]);
  }
}

/// The offered sizes, under a heading per ratio, plus a custom entry.
class _SizeGroups extends StatelessWidget {
  const _SizeGroups({
    required this.screen,
    required this.isSelected,
    required this.onTap,
    required this.custom,
  });

  final Resolution screen;
  final bool Function(Resolution) isSelected;
  final ValueChanged<Resolution> onTap;
  final VoidCallback custom;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final ResolutionBucket bucket in offerableResolutions(screen))
          _group(context, l10n, bucket),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: custom,
            icon: const Icon(Icons.add),
            label: Text(l10n.resolutionCustom),
          ),
        ),
      ],
    );
  }

  Widget _group(
    BuildContext context,
    AppLocalizations l10n,
    ResolutionBucket bucket,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            ratioLabel(l10n, bucket.ratio),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final Resolution size in bucket.sizes)
                FilterChip(
                  label: Text(resolutionLabel(l10n, size, screen: screen)),
                  selected: isSelected(size),
                  onSelected: (bool _) => onTap(size),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for a width and a height, and reports the size when both are valid.
///
/// A dialog rather than two fields in the sheet: a half-typed `1920x` is not a
/// resolution, and a filter that re-queries Wallhaven on every keystroke would
/// spend the 45 req/min budget on prefixes — the same reason search runs on
/// submit.
Future<void> _askForSize(
  BuildContext context,
  AppLocalizations l10n,
  ValueChanged<Resolution> onPicked,
) async {
  final Resolution? size = await showDialog<Resolution>(
    context: context,
    builder: (BuildContext context) => const _CustomSizeDialog(),
  );
  if (size != null) onPicked(size);
}

/// The custom width × height entry.
class _CustomSizeDialog extends StatefulWidget {
  const _CustomSizeDialog();

  @override
  State<_CustomSizeDialog> createState() => _CustomSizeDialogState();
}

class _CustomSizeDialogState extends State<_CustomSizeDialog> {
  final TextEditingController _width = TextEditingController();
  final TextEditingController _height = TextEditingController();

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.resolutionCustom),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(child: _field(_width, l10n.resolutionWidth)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('×'),
          ),
          Flexible(child: _field(_height, l10n.resolutionHeight)),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.resolutionAdd)),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      onSubmitted: (String _) => _submit(),
    );
  }

  /// Refuses anything that is not a real size, rather than sending it.
  ///
  /// Wallhaven answers an unparseable `resolutions` with an *empty grid*, not
  /// an error, so a typo would read as "no wallpapers are this size" — which is
  /// a lie, and an unfixable-looking one.
  void _submit() {
    final Resolution? size = Resolution.tryParse(
      '${_width.text.trim()}x${_height.text.trim()}',
    );
    if (size == null) return;
    Navigator.of(context).pop(size);
  }
}
