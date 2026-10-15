// How Device Sync names another device: a short tag that never collides with
// another tag shown beside it, and a "last shared" line rounded to the day.
import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/screens/settings/sync_device_labels.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('syncDeviceTags', () {
    test('is the first six characters when those are already unique', () {
      expect(syncDeviceTags(['k7mQ2xAAAA', '7c02LmBBBB']), {
        'k7mQ2xAAAA': 'k7mQ2x',
        '7c02LmBBBB': '7c02Lm',
      });
    });

    test('lengthens both of two tags that would be equal, and no other', () {
      expect(syncDeviceTags(['abcdefgh1', 'abcdefgh2', 'zyxwvuts']), {
        'abcdefgh1': 'abcdefgh1',
        'abcdefgh2': 'abcdefgh2',
        'zyxwvuts': 'zyxwvu',
      });
      expect(syncDeviceTags(['abcdef1xxx', 'abcdef2yyy']), {
        'abcdef1xxx': 'abcdef1',
        'abcdef2yyy': 'abcdef2',
      });
    });

    test('every tag is unique among those computed together', () {
      final ids = [
        'aaaaaaa1',
        'aaaaaaa2',
        'aaaaaab3',
        'aaaaab44',
        'bbbbbbbb',
        'aaaaaaa',
      ];
      final tags = syncDeviceTags(ids);
      expect(tags.values.toSet(), hasLength(ids.length));
      for (final id in ids) {
        expect(id.startsWith(tags[id]!), isTrue, reason: id);
        expect(tags[id]!.length, greaterThanOrEqualTo(6));
      }
    });

    test('an identifier shorter than six characters is shown whole', () {
      expect(syncDeviceTags(['abc']), {'abc': 'abc'});
    });
  });

  group('syncDaysSince', () {
    test('counts calendar days, not elapsed hours', () {
      final now = DateTime(2026, 10, 2, 0, 30);
      expect(syncDaysSince(DateTime(2026, 10, 1, 23, 45), now), 1);
      expect(syncDaysSince(DateTime(2026, 10, 2, 0, 1), now), 0);
      expect(syncDaysSince(DateTime(2026, 9, 2, 12), now), 30);
    });

    test('a peer clock ahead of this one reads as today', () {
      final now = DateTime(2026, 10, 2, 12);
      expect(syncDaysSince(now.add(const Duration(days: 2)), now), 0);
    });
  });

  group('syncLastSharedText', () {
    late AppLocalizations l10n;

    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    String at(int daysAgo) {
      final now = DateTime(2026, 10, 2, 12);
      return syncLastSharedText(
        l10n,
        now.subtract(Duration(days: daysAgo)),
        now,
      );
    }

    test('today, yesterday, days up to two weeks, then rounded weeks', () {
      expect(at(0), 'Last shared changes today');
      expect(at(1), 'Last shared changes yesterday');
      expect(at(13), 'Last shared changes 13 days ago');
      expect(at(14), 'Last shared changes about 2 weeks ago');
      expect(at(24), 'Last shared changes about 3 weeks ago');
      expect(at(70), 'Last shared changes about 10 weeks ago');
    });
  });
}
