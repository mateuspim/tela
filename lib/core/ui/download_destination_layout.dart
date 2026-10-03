import 'package:flutter/material.dart';

/// Lays out the download chooser's two groups: where the file goes, and how it
/// is filed and remembered.
///
/// Stacked on a narrow screen. Side by side where there is room, because
/// stacked they overran a landscape tablet's height and the last switch was cut
/// mid-subtitle at the scroll edge (device pass F3, 2026-10-03) — which reads
/// as clipped rather than as "scroll for more". Either way it caps its own
/// measure and scrolls rather than clipping, since an `AlertDialog` does not
/// cap its width and would stretch on a tablet.
///
/// ```dart
/// DownloadDestinationLayout(destinations: cards, options: switches)
/// ```
class DownloadDestinationLayout extends StatelessWidget {
  /// Creates the layout.
  const DownloadDestinationLayout({
    required this.destinations,
    required this.options,
    super.key,
  });

  /// The warnings that qualify the choice, then a card per destination.
  final List<Widget> destinations;

  /// The tag row and the "keep" switches.
  final List<Widget> options;

  /// Wide enough for the longest destination detail on two lines, narrow enough
  /// that the cards still read as a stack of choices on a tablet.
  static const double columnWidth = 360;

  /// Gutter between the two columns of the side-by-side layout.
  static const double columnGap = 24;

  /// The narrowest screen with room for both columns: their 744 dp, the
  /// dialog's 24 dp padding a side, and its 40 dp inset from the screen edge.
  static const double sideBySideMinWidth = 900;

  @override
  Widget build(BuildContext context) {
    final bool sideBySide =
        MediaQuery.sizeOf(context).width >= sideBySideMinWidth;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: sideBySide ? columnWidth * 2 + columnGap : columnWidth,
      ),
      child: SingleChildScrollView(
        child: sideBySide ? _columns() : _stack(),
      ),
    );
  }

  Widget _stack() {
    return _column(<Widget>[
      ...destinations,
      const Divider(height: 8),
      ...options,
    ]);
  }

  /// Fixed column widths, not `Expanded`: `AlertDialog` sizes its child by
  /// intrinsic width, and a flexed row there is sized by its widest guess.
  Widget _columns() {
    return Row(
      key: const Key('download-destination-columns'),
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: columnGap,
      children: <Widget>[
        SizedBox(width: columnWidth, child: _column(destinations)),
        SizedBox(width: columnWidth, child: _column(options)),
      ],
    );
  }

  Widget _column(List<Widget> children) =>
      Column(mainAxisSize: MainAxisSize.min, spacing: 8, children: children);
}
