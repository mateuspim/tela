import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A tappable row that pushes one of the library's child screens.
///
/// Shared by the Library tab and the Settings screen so the way into the
/// download history or the private library reads the same wherever it is
/// offered, and the icon-and-chevron layout lives in one place.
///
/// ```dart
/// LibraryDestinationTile(
///   icon: Icons.history_outlined,
///   title: l10n.downloadHistoryTitle,
///   subtitle: l10n.downloadHistoryOpenDetail,
///   routeName: TelaRoutes.downloadHistoryName,
/// );
/// ```
class LibraryDestinationTile extends StatelessWidget {
  /// Creates a tile that opens [routeName] when tapped.
  const LibraryDestinationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.routeName,
    super.key,
  });

  /// The leading glyph — a clock for history, a lock for the private library.
  final IconData icon;

  /// The destination's name.
  final String title;

  /// A one-line description of what waits there.
  final String subtitle;

  /// The go_router route pushed on tap.
  final String routeName;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.pushNamed(routeName),
    );
  }
}
