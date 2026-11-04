import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations_en.dart';
import 'package:tela/core/ui/duration_text.dart';

void main() {
  final AppLocalizationsEn l10n = AppLocalizationsEn();

  test('under a minute reads as such', () {
    expect(formatDuration(l10n, const Duration(seconds: 59)), 'under a minute');
  });

  test('a part minute rounds up', () {
    expect(formatDuration(l10n, const Duration(seconds: 61)), '2 min');
  });

  test('an hour or more names both', () {
    expect(formatDuration(l10n, const Duration(minutes: 65)), '1 h 5 min');
  });
}
