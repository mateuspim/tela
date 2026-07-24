import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/download_destination_streak.dart';
import 'package:tela/domain/models/storage_tier.dart';

void main() {
  group('extending', () {
    test('starts at one when there is nothing to extend', () {
      final DownloadDestinationStreak streak =
          DownloadDestinationStreak.extending(null, StorageTier.appPrivate);

      expect(streak.tier, StorageTier.appPrivate);
      expect(streak.length, 1);
    });

    test('grows while the destination keeps matching', () {
      DownloadDestinationStreak? streak;
      for (int i = 0; i < 3; i++) {
        streak = DownloadDestinationStreak.extending(
          streak,
          StorageTier.appPrivate,
        );
      }

      expect(streak?.length, 3);
    });

    // The reset is the half that matters: a run that survived a download
    // somewhere else would suggest a destination the user has just moved away
    // from, which is worse than suggesting nothing.
    test('resets to one when the destination changes', () {
      final DownloadDestinationStreak private = DownloadDestinationStreak(
        tier: StorageTier.appPrivate,
        length: 7,
      );

      final DownloadDestinationStreak moved =
          DownloadDestinationStreak.extending(
            private,
            StorageTier.sharedGallery,
          );

      expect(moved.tier, StorageTier.sharedGallery);
      expect(moved.length, 1);
    });
  });

  group('encoding', () {
    test('round-trips through the stored form', () {
      final DownloadDestinationStreak streak = DownloadDestinationStreak(
        tier: StorageTier.filesOutsideGallery,
        length: 4,
      );

      expect(streak.encode(), 'filesOutsideGallery:4');
      expect(DownloadDestinationStreak.tryParse(streak.encode()), streak);
    });

    // A row this cannot read costs a suggestion, so every unreadable shape has
    // to answer null rather than guess — including a renamed enum constant,
    // which is the realistic one.
    test('answers null for anything it did not write', () {
      const List<String?> junk = <String?>[
        null,
        '',
        'appPrivate',
        'appPrivate:',
        'appPrivate:0',
        'appPrivate:-2',
        'appPrivate:many',
        'privateLibrary:3',
        'appPrivate:3:3',
      ];

      for (final String? stored in junk) {
        expect(
          DownloadDestinationStreak.tryParse(stored),
          isNull,
          reason: 'should not parse "$stored"',
        );
      }
    });
  });

  test('a streak of zero is spelled null, never constructed', () {
    expect(
      () => DownloadDestinationStreak(tier: StorageTier.appPrivate, length: 0),
      throwsArgumentError,
    );
  });
}
