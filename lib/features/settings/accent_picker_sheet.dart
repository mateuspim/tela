import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';

/// A compact HSV colour picker for choosing any accent.
///
/// Built on Flutter's own [HSVColor], so the maths that turns a drag into a
/// colour is the framework's, not ours: a saturation/brightness panel over a
/// hue slider, the two controls every native picker splits a colour into.
///
/// ```dart
/// final Color? picked = await AccentPickerSheet.show(context, initial: seed);
/// ```
class AccentPickerSheet extends StatefulWidget {
  /// Creates the picker seeded at [initial].
  const AccentPickerSheet({required this.initial, super.key});

  /// The colour the picker opens on.
  final Color initial;

  /// Opens the picker as a modal sheet, resolving to the chosen colour or null
  /// when dismissed without confirming.
  static Future<Color?> show(BuildContext context, {required Color initial}) {
    return showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => AccentPickerSheet(initial: initial),
    );
  }

  @override
  State<AccentPickerSheet> createState() => _AccentPickerSheetState();
}

class _AccentPickerSheetState extends State<AccentPickerSheet> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  Color get _color => _hsv.toColor();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(l10n.accentPickerTitle, style: text.titleLarge),
            const SizedBox(height: 16),
            _SvPanel(
              hue: _hsv.hue,
              saturation: _hsv.saturation,
              value: _hsv.value,
              semanticLabel: l10n.accentPickerSaturation,
              onChanged: (double s, double v) => setState(
                () => _hsv = _hsv.withSaturation(s).withValue(v),
              ),
            ),
            const SizedBox(height: 16),
            _HueSlider(
              hue: _hsv.hue,
              semanticLabel: l10n.accentPickerHue,
              onChanged: (double h) => setState(() => _hsv = _hsv.withHue(h)),
            ),
            const SizedBox(height: 20),
            _preview(text),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_color),
              child: Text(l10n.accentPickerConfirm),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(TextTheme text) {
    return Row(
      children: <Widget>[
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black.withValues(alpha: .15)),
          ),
        ),
        const SizedBox(width: 14),
        Text(_hex, style: text.titleMedium?.copyWith(letterSpacing: .5)),
      ],
    );
  }

  /// The `#RRGGBB` the swatch and settings row will store.
  String get _hex {
    final int rgb = _color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

/// The saturation (x) × brightness (y) plane at a fixed hue.
class _SvPanel extends StatelessWidget {
  const _SvPanel({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.semanticLabel,
    required this.onChanged,
  });

  final double hue;
  final double saturation;
  final double value;
  final String semanticLabel;
  final void Function(double saturation, double value) onChanged;

  static const double _height = 190;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size size = Size(constraints.maxWidth, _height);
          return GestureDetector(
            onPanDown: (DragDownDetails d) => _emit(d.localPosition, size),
            onPanUpdate: (DragUpdateDetails d) => _emit(d.localPosition, size),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: size.width,
                height: _height,
                child: CustomPaint(
                  painter: _SvPainter(hue: hue),
                  foregroundPainter: _ThumbPainter(
                    Offset(saturation * size.width, (1 - value) * _height),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _emit(Offset local, Size size) {
    final double s = (local.dx / size.width).clamp(0.0, 1.0);
    final double v = (1 - local.dy / size.height).clamp(0.0, 1.0);
    onChanged(s, v);
  }
}

/// The rainbow hue bar, 0–360°.
class _HueSlider extends StatelessWidget {
  const _HueSlider({
    required this.hue,
    required this.semanticLabel,
    required this.onChanged,
  });

  final double hue;
  final String semanticLabel;
  final ValueChanged<double> onChanged;

  static const double _height = 30;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      slider: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth;
          return GestureDetector(
            onPanDown: (DragDownDetails d) => _emit(d.localPosition.dx, width),
            onPanUpdate: (DragUpdateDetails d) =>
                _emit(d.localPosition.dx, width),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: SizedBox(
                width: width,
                height: _height,
                child: CustomPaint(
                  painter: const _HuePainter(),
                  foregroundPainter: _ThumbPainter(
                    Offset(hue / 360 * width, _height / 2),
                    horizontal: true,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _emit(double dx, double width) =>
      onChanged((dx / width).clamp(0.0, 1.0) * 360);
}

/// Paints the white→hue then transparent→black double gradient of the SV plane.
class _SvPainter extends CustomPainter {
  const _SvPainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Color pure = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas
      ..drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: <Color>[Colors.white, pure],
          ).createShader(rect),
      )
      ..drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Colors.transparent, Colors.black],
          ).createShader(rect),
      );
  }

  @override
  bool shouldRepaint(_SvPainter old) => old.hue != hue;
}

/// Paints the full-spectrum hue bar.
class _HuePainter extends CustomPainter {
  const _HuePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            for (int h = 0; h <= 360; h += 60)
              HSVColor.fromAHSV(1, h.toDouble() % 360, 1, 1).toColor(),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => false;
}

/// A ring marking the current position on either control.
class _ThumbPainter extends CustomPainter {
  const _ThumbPainter(this.center, {this.horizontal = false});

  final Offset center;
  final bool horizontal;

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = horizontal ? size.height / 2 - 2 : 9;
    canvas
      ..drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      )
      ..drawCircle(
        center,
        radius + 1.5,
        Paint()
          ..color = Colors.black.withValues(alpha: .35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
  }

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      old.center != center || old.horizontal != horizontal;
}
