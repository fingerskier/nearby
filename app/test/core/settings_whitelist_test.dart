import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nearby/src/core/address.dart';
import 'package:nearby/src/core/format.dart';
import 'package:nearby/src/core/settings.dart';
import 'package:nearby/src/core/whitelist.dart';

import '../fakes.dart';

void main() {
  group('Settings', () {
    test('round-trips through JSON', () {
      const settings = Settings(
        n: 2.7,
        alertRadius: 4,
        scanOffSeconds: 20,
        calibrations: {'AA:00:00:00:00:01': -62},
        alertRotating: true,
      );
      final copy = Settings.fromJson(jsonDecode(jsonEncode(settings.toJson())));
      expect(copy.toJson(), settings.toJson());
    });

    test('falls back per field on malformed input and clamps numbers', () {
      final settings = Settings.fromJson({
        'n': 99,
        'ref1m': 'loud',
        'ping': 'yes',
        'calibrations': ['AA:00:00:00:00:01'],
        'alertRadius': -3,
        'scanOffSeconds': double.nan,
      });
      expect(settings.n, Settings.nLimit.max);
      expect(settings.ref1m, const Settings().ref1m);
      expect(settings.ping, isTrue);
      expect(settings.calibrations, isEmpty);
      expect(settings.alertRadius, Settings.alertRadiusLimit.min);
      expect(settings.scanOffSeconds, 0);
      expect(Settings.fromJson(null).toJson(), const Settings().toJson());
    });

    test('copyWith can clear the alert radius', () {
      const settings = Settings(alertRadius: 3);
      expect(settings.copyWith(n: 3).alertRadius, 3);
      expect(settings.copyWith(alertRadius: null).alertRadius, isNull);
    });

    test('never counts a device away within one scan cycle', () {
      expect(const Settings(outOfRangeSeconds: 60).awayAfter, const Duration(seconds: 60));
      expect(
        const Settings(outOfRangeSeconds: 30, scanOnSeconds: 10, scanOffSeconds: 60).awayAfter,
        const Duration(seconds: 75),
      );
    });
  });

  group('Whitelist', () {
    test('normalizes addresses and rejects junk and duplicates', () {
      final whitelist = Whitelist();
      expect(whitelist.add('aa:bb:cc:dd:ee:ff', at: t0), isTrue);
      expect(whitelist.contains('AA:BB:CC:DD:EE:FF'), isTrue);
      expect(whitelist.add('AA:BB:CC:DD:EE:FF', at: t0), isFalse);
      expect(whitelist.add('not an address', at: t0), isFalse);
      expect(whitelist.length, 1);
    });

    test('round-trips through JSON, skipping malformed entries', () {
      final whitelist = Whitelist()
        ..add('AA:00:00:00:00:01', name: 'Lamp', at: t0)
        ..add('AA:00:00:00:00:02', label: 'Front door', at: t0);
      final raw = jsonDecode(jsonEncode(whitelist.toJson())) as List<Object?>;
      final copy = Whitelist.fromJson([
        ...raw,
        42,
        {'address': 7},
        {'address': 'nope'},
      ]);
      expect(copy.entries.map((e) => e.address), ['AA:00:00:00:00:01', 'AA:00:00:00:00:02']);
      expect(copy['AA:00:00:00:00:01']!.name, 'Lamp');
      expect(copy['AA:00:00:00:00:02']!.label, 'Front door');
      expect(copy['AA:00:00:00:00:02']!.added, t0);
      expect(Whitelist.fromJson({'not': 'a list'}).length, 0);
    });

    test('rename trims, and an empty label falls back to the advertised name', () {
      final whitelist = Whitelist()..add('AA:00:00:00:00:01', name: 'Lamp', at: t0);
      whitelist.rename('AA:00:00:00:00:01', '  Desk lamp ');
      expect(whitelist['AA:00:00:00:00:01']!.label, 'Desk lamp');
      whitelist.rename('AA:00:00:00:00:01', ' ');
      expect(whitelist['AA:00:00:00:00:01']!.label, isNull);
      expect(whitelist['AA:00:00:00:00:01']!.name, 'Lamp');
    });
  });

  group('format', () {
    test('labels a device by user label, then name, then maker', () {
      expect(deviceLabel(label: 'Mine', name: 'Lamp', manufacturer: 0x004C), 'Mine');
      expect(deviceLabel(name: 'Lamp', manufacturer: 0x004C), 'Lamp');
      expect(deviceLabel(name: '', manufacturer: 0x004C), 'Unnamed Apple device');
      expect(deviceLabel(manufacturer: 0xFFFF), 'Unnamed device');
    });

    test('formats distances, ages and countdowns', () {
      expect(formatDistance(3.14), '3.1 m');
      expect(formatDistance(12.6), '13 m');
      expect(formatAge(const Duration(milliseconds: 900)), 'now');
      expect(formatAge(const Duration(seconds: 42)), '42 s');
      expect(formatAge(const Duration(minutes: 5, seconds: 10)), '5 min');
      expect(formatCountdown(const Duration(seconds: 61, milliseconds: 200)), '1:02');
      expect(formatCountdown(const Duration(seconds: -3)), '0:00');
    });

    test('names every address kind', () {
      expect(AddressKind.values.map(kindLabel), ['public', 'static', 'rotating', 'anonymous']);
    });
  });
}
