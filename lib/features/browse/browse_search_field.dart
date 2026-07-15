import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/features/browse/browse_query_controller.dart';

/// The search term, as the browse app bar's title.
///
/// Submitting is what searches — not every keystroke. Wallhaven allows 45
/// requests a minute, and search-as-you-type would spend them on prefixes of a
/// word the user has not finished typing.
class BrowseSearchField extends ConsumerStatefulWidget {
  /// Creates the search field.
  const BrowseSearchField({super.key});

  @override
  ConsumerState<BrowseSearchField> createState() => _BrowseSearchFieldState();
}

class _BrowseSearchFieldState extends ConsumerState<BrowseSearchField> {
  final TextEditingController _entry = TextEditingController();

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return TextField(
      controller: _entry,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: l10n.browseSearchHint,
        suffixIcon: _entry.text.isEmpty ? null : _clearButton(l10n),
      ),
      onChanged: (String _) => setState(() {}),
      onSubmitted: _search,
    );
  }

  Widget _clearButton(AppLocalizations l10n) {
    return IconButton(
      icon: const Icon(Icons.close),
      tooltip: l10n.browseSearchClear,
      onPressed: _clear,
    );
  }

  void _search(String term) {
    ref.read(browseQueryProvider.notifier).search(term);
  }

  /// Clearing the field also clears the *listing* — a cleared box that still
  /// shows results for the old term reads as broken.
  void _clear() {
    _entry.clear();
    setState(() {});
    ref.read(browseQueryProvider.notifier).search('');
  }
}
