import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/features/browse/browse_query_controller.dart';
import 'package:tela/features/browse/browse_search_draft.dart';
import 'package:tela/features/browse/wallpaper_id_chip.dart';

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
        // Unfilled and borderless: the FloatingCapsule around it is the
        // field's surface, and a second fill inside it reads as a box in a box.
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        prefixIcon: const Icon(Icons.search),
        hintText: l10n.browseSearchHint,
        // Inside the field rather than under it: the field is mostly empty
        // space on a tablet, and anything below it either shoves the tabs down
        // or covers the first thumbnail. See WallpaperIdChip for both attempts.
        suffix: const WallpaperIdChip(),
        suffixIcon: _entry.text.isEmpty ? null : _clearButton(l10n),
      ),
      onChanged: _draft,
      // Untouched on purpose: Enter runs an ordinary text search even when the
      // text is id-shaped. The chip is an offer beside this, never in place of
      // it — a six-character search term must not be intercepted.
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

  /// The rebuild is for the clear button; the draft is for the id-jump chip,
  /// which sits in the app bar's bottom and cannot see this controller.
  void _draft(String text) {
    setState(() {});
    ref.read(browseSearchDraftProvider.notifier).typed = text;
  }

  void _search(String term) {
    ref.read(browseQueryProvider.notifier).search(term);
  }

  /// Clearing the field also clears the *listing* — a cleared box that still
  /// shows results for the old term reads as broken.
  void _clear() {
    _entry.clear();
    setState(() {});
    ref.read(browseSearchDraftProvider.notifier).typed = '';
    ref.read(browseQueryProvider.notifier).search('');
  }
}
