import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/wallhaven/wallhaven_mapper.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';

Map<String, dynamic> _fixture(String name) {
  final String raw = File('test/fixtures/$name').readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

void main() {
  group('WallhavenMapper.toDetails', () {
    test(
      'maps a captured /w/{id} response to non-nullable detail metadata',
      () {
        final WallpaperDetails details = WallhavenMapper.toDetails(
          _fixture('wallpaper_detail.json'),
        );

        expect(details.wallpaper.id, 'e7jvjd');
        expect(
          details.wallpaper.fullImageUrl,
          endsWith('wallhaven-e7jvjd.jpg'),
        );
        expect(details.ratio, '1.78');
        expect(details.fileType, 'image/jpeg');
        expect(details.wallpaper.fileSizeBytes, 1048576);
        expect(details.wallpaper.category, Category.general);
        expect(details.wallpaper.purity, Purity.sfw);
        expect(details.wallpaper.colors, <String>[
          '#660000',
          '#000000',
          '#424153',
        ]);
        expect(details.tags.map((WallpaperTag tag) => tag.name), <String>[
          'landscape',
          'sunset',
        ]);
        expect(details.uploader.username, 'tela-fixture');
        expect(details.source, 'https://example.com/original-art');
        expect(details.views, 4523);
        expect(details.favorites, 128);
      },
    );

    test('rejects a detail response without its required uploader', () {
      expect(
        () => WallhavenMapper.toDetails(<String, dynamic>{
          'data': <String, dynamic>{
            'id': 'x',
            'path': 'https://example.com/x.jpg',
            'resolution': '1x1',
            'purity': 'sfw',
            'category': 'general',
            'thumbs': <String, dynamic>{
              'small': 'https://example.com/s.jpg',
              'large': 'https://example.com/l.jpg',
              'original': 'https://example.com/o.jpg',
            },
            'ratio': '1',
            'file_type': 'image/jpeg',
          },
        }),
        throwsA(isA<UnexpectedResponseFailure>()),
      );
    });
  });

  group('WallhavenMapper.toPage', () {
    test('maps a captured /search response', () {
      final WallpaperPage page = WallhavenMapper.toPage(
        _fixture('search_page.json'),
      );

      expect(page.wallpapers, hasLength(2));
      expect(page.currentPage, 2);
      expect(page.lastPage, 37);
      expect(page.seed, 'abc123');
      expect(page.hasMore, isTrue);
      // The permalink comes off the wire; the model no longer composes one,
      // because only the adapter knows its site's URL shape.
      expect(
        page.wallpapers.first.pageUrl,
        Uri.parse('https://wallhaven.cc/w/e7jvjd'),
      );
      expect(page.wallpapers.first.source, SourceId.wallhaven);
    });

    test('maps each wallpaper to the domain shape, not the wire shape', () {
      final WallpaperPage page = WallhavenMapper.toPage(
        _fixture('search_page.json'),
      );
      final Wallpaper first = page.wallpapers.first;

      expect(first.id, 'e7jvjd');
      expect(first.fullImageUrl, endsWith('wallhaven-e7jvjd.jpg'));
      expect(first.thumbSmallUrl, contains('/small/'));
      expect(first.thumbLargeUrl, contains('/lg/'));
      // The grid renders this one: `small` and `large` are fixed-crop and would
      // center-punch a landscape into a close-up.
      expect(first.thumbOriginalUrl, contains('/orig/'));
      expect(first.resolution, const Resolution(3840, 2160));
      expect(first.fileSizeBytes, 1048576);
      expect(first.purity, Purity.sfw);
      expect(first.category, Category.general);
      expect(first.colors, <String>['#660000', '#000000', '#424153']);
      expect(first.isNsfw, isFalse);
    });

    test('handles sketchy/anime and an empty colour list', () {
      final WallpaperPage page = WallhavenMapper.toPage(
        _fixture('search_page.json'),
      );
      final Wallpaper second = page.wallpapers[1];

      expect(second.purity, Purity.sketchy);
      expect(second.category, Category.anime);
      expect(second.colors, isEmpty);
      expect(second.resolution.isPortrait, isTrue);
    });

    test('reports hasMore false on the final page', () {
      final WallpaperPage page = WallhavenMapper.toPage(<String, dynamic>{
        'data': <dynamic>[],
        'meta': <String, dynamic>{'current_page': 37, 'last_page': 37},
      });

      expect(page.hasMore, isFalse);
      expect(page.wallpapers, isEmpty);
    });

    test("carries Wallhaven's own total, not a page-count guess", () {
      // `last_page * per_page` over-reports by up to a page, because the last
      // page is short — and this number is what a user reads before committing
      // to downloading the whole listing.
      final WallpaperPage page = WallhavenMapper.toPage(<String, dynamic>{
        'data': <dynamic>[],
        'meta': <String, dynamic>{
          'current_page': 1,
          'last_page': 518,
          'per_page': 24,
          'total': 12431,
        },
      });

      expect(page.total, 12431);
    });

    test('a source that publishes no total says null, not zero', () {
      // Null is "this source does not count", which a screen must be able to
      // tell from a listing genuinely holding nothing.
      final WallpaperPage page = WallhavenMapper.toPage(<String, dynamic>{
        'data': <dynamic>[],
        'meta': <String, dynamic>{'current_page': 1, 'last_page': 1},
      });

      expect(page.total, isNull);
    });

    test('fails soft on a payload shape Wallhaven never promised to keep', () {
      // The ToS reserves the right to change the API without notice, so a
      // surprise shape must be a typed failure, not a TypeError in the grid.
      expect(
        () => WallhavenMapper.toPage(<String, dynamic>{'data': 'nope'}),
        throwsA(isA<UnexpectedResponseFailure>()),
      );
      expect(
        () => WallhavenMapper.toPage(<String, dynamic>{
          'data': <dynamic>[
            <String, dynamic>{'id': 'x'},
          ],
        }),
        throwsA(isA<UnexpectedResponseFailure>()),
      );
    });
  });

  group('WallhavenMapper.toAccountSettings', () {
    test('maps a captured /settings response to the account defaults', () {
      final AccountSettings account = WallhavenMapper.toAccountSettings(
        _fixture('account_settings.json'),
      );

      expect(account.categories.encodeStored(), '110');
      expect(account.topRange, TopRange.oneWeek);
    });

    test("does not read the account's purity at all — browse opens on safe, "
        'whatever the account browses on', () {
      // The fixture's account allows sketchy. Nothing in the domain model can
      // carry that, which is the point: it cannot be honoured by accident.
      final AccountSettings account = _account(<String, dynamic>{
        'purity': <String>['sfw', 'sketchy', 'nsfw'],
        'categories': <String>['anime'],
      });

      expect(
        account.toBrowseDefaults().applyTo(const SearchQuery()).purity.purities,
        <Purity>{Purity.sfw},
      );
    });

    test('an unreadable name costs that name, not the sync', () {
      final AccountSettings account = _account(<String, dynamic>{
        'categories': <String>['anime', 'memes'],
        'toplist_range': '1w',
      });

      expect(account.categories.encodeStored(), '010');
      expect(account.topRange, TopRange.oneWeek);
    });

    test("a filter the account never narrowed is tela's own", () {
      // Wallhaven sends [] for "no preference"; the encoder would throw on the
      // "000" mask that literally translates to.
      final AccountSettings account = _account(<String, dynamic>{
        'categories': <String>[],
      });

      expect(account.categories.encodeStored(), '111');
    });

    test('an unreadable toplist range costs the range', () {
      expect(
        _account(<String, dynamic>{'toplist_range': 'forever'}).topRange,
        TopRange.oneMonth,
      );
      expect(
        _account(<String, dynamic>{}).topRange,
        TopRange.oneMonth,
      );
    });

    test('fails soft on a payload shape Wallhaven never promised to keep', () {
      expect(
        () => WallhavenMapper.toAccountSettings(<String, dynamic>{
          'data': 'nope',
        }),
        throwsA(isA<UnexpectedResponseFailure>()),
      );
    });
  });
}

/// The account defaults of a `/settings` body carrying only [data].
AccountSettings _account(Map<String, dynamic> data) {
  return WallhavenMapper.toAccountSettings(<String, dynamic>{'data': data});
}
