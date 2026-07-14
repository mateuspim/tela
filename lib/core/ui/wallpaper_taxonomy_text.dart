import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';

/// The user-facing name of a [Category].
///
/// Shared by the browse filter sheet and the detail metadata, so a wallpaper is
/// not filed under "People" in one place and `people` in the other.
///
/// ```dart
/// categoryLabel(l10n, Category.anime); // 'Anime'
/// ```
String categoryLabel(AppLocalizations l10n, Category category) {
  return switch (category) {
    Category.general => l10n.categoryGeneral,
    Category.anime => l10n.categoryAnime,
    Category.people => l10n.categoryPeople,
  };
}

/// The user-facing name of a [Purity].
///
/// The enum's own `name` is Wallhaven's wire value (`sfw`), which is not a
/// thing to show a person — and not translatable.
String purityLabel(AppLocalizations l10n, Purity purity) {
  return switch (purity) {
    Purity.sfw => l10n.puritySfw,
    Purity.sketchy => l10n.puritySketchy,
    Purity.nsfw => l10n.purityNsfw,
  };
}
