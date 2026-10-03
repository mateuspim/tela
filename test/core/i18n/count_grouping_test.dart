import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';

void main() {
  final AppLocalizations l10n = lookupAppLocalizations(const Locale('en'));

  // Regression for device pass F2 (2026-10-03): a whole-tag download read
  // "Download 19714 wallpapers to", with no grouping.
  test('counts are grouped in the chooser title', () {
    expect(
      l10n.batchDownloadChooseTier(19714),
      'Download 19,714 wallpapers to',
    );
  });

  test('counts are grouped in the download-all confirmation', () {
    expect(
      l10n.listingDownloadAllCounted(19714, '16.6 GB'),
      '19,714 wallpapers, roughly 16.6 GB',
    );
  });

  test('a count of one still picks the singular', () {
    expect(l10n.batchDownloadChooseTier(1), 'Download 1 wallpaper to');
  });
}
