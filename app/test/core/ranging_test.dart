import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nearby/src/core/address.dart';
import 'package:nearby/src/core/distance.dart';
import 'package:nearby/src/core/kalman.dart';
import 'package:nearby/src/core/radar_scale.dart';
import 'package:nearby/src/core/settings.dart';
import 'package:nearby/src/core/tracker.dart';

import '../fakes.dart';

void main() {
  group('distance', () {
    const model = PathLoss(ref1m: -59, n: 2);

    test('is 1 m at the reference and grows tenfold per 10·n dB', () {
      expect(distanceFromRssi(-59, model), closeTo(1, 1e-9));
      expect(distanceFromRssi(-79, model), closeTo(10, 1e-9));
    });

    test('inverts rssiAtDistance', () {
      for (final d in [0.5, 1.0, 3.7, 20.0]) {
        expect(distanceFromRssi(rssiAtDistance(d, model), model), closeTo(d, 1e-9));
      }
    });

    test('clamps to the useful range', () {
      expect(distanceFromRssi(0, model), minDistance);
      expect(distanceFromRssi(-200, model), maxDistance);
    });

    test('prefers calibration, then TX power, then the default', () {
      expect(resolveRef1m(calibrated: -50, txPower: 0, useTxPower: true, fallback: -59), -50);
      // 0 dBm is a real TX power (many Apple devices advertise it), not "missing".
      expect(resolveRef1m(txPower: 0, useTxPower: true, fallback: -59), -41);
      expect(resolveRef1m(txPower: 0, useTxPower: false, fallback: -59), -59);
      expect(resolveRef1m(useTxPower: true, fallback: -59), -59);
    });
  });

  group('Kalman1D', () {
    test('passes the first reading through, then smooths noise', () {
      final filter = Kalman1D(Settings.processNoise, 16);
      final random = math.Random(1);
      expect(filter.update(-60, t0), -60);
      final estimates = <double>[];
      for (var i = 1; i <= 200; i++) {
        final noisy = -70 + (random.nextDouble() - 0.5) * 16;
        estimates.add(filter.update(noisy, t0.add(Duration(milliseconds: 200 * i))));
      }
      final tail = estimates.skip(100);
      final mean = tail.reduce((a, b) => a + b) / tail.length;
      expect(mean, closeTo(-70, 1));
      final spread = tail.map((e) => (e - mean).abs()).reduce(math.max);
      expect(spread, lessThan(4));
    });

    test('trusts a reading more after a long silence', () {
      final quick = Kalman1D(1, 16)..update(-60, t0);
      final slow = Kalman1D(1, 16)..update(-60, t0);
      final afterSecond = quick.update(-80, t0.add(const Duration(seconds: 1)));
      final afterMinute = slow.update(-80, t0.add(const Duration(minutes: 1)));
      expect(afterMinute, lessThan(afterSecond));
    });
  });

  group('classifyAddress', () {
    test('reads the random address subtype from the top two bits', () {
      expect(classifyAddress('C1:75:00:00:00:01', 'random'), AddressKind.staticRandom);
      expect(classifyAddress('6E:1B:00:00:00:01', 'random'), AddressKind.resolvable);
      expect(classifyAddress('1D:12:00:00:00:01', 'random'), AddressKind.nonResolvable);
    });

    test('treats public and unknown types as public', () {
      expect(classifyAddress('6E:1B:00:00:00:01', 'public'), AddressKind.public);
      expect(classifyAddress('6E:1B:00:00:00:01', null), AddressKind.public);
    });

    test('only public and static addresses are stable', () {
      expect(AddressKind.values.where((kind) => kind.isStable), [AddressKind.public, AddressKind.staticRandom]);
    });
  });

  group('Tracker', () {
    test('ranges from the smoothed RSSI and keeps names once seen', () {
      final tracker = Tracker(const Settings());
      tracker.ingest(sight('AA:00:00:00:00:01', at: t0, rssi: -59, name: 'Lamp'));
      final device = tracker.ingest(sight('AA:00:00:00:00:01', at: t0.add(const Duration(seconds: 1)), rssi: -59));
      expect(device.name, 'Lamp');
      expect(device.distance, closeTo(1, 1e-6));
      expect(device.count, 2);
    });

    test('uses a calibration and re-ranges when settings change', () {
      final tracker = Tracker(const Settings());
      tracker.ingest(sight('AA:00:00:00:00:01', at: t0, rssi: -70));
      expect(tracker['AA:00:00:00:00:01']!.distance, greaterThan(3));
      tracker.configure(const Settings(calibrations: {'AA:00:00:00:00:01': -70}));
      expect(tracker['AA:00:00:00:00:01']!.distance, closeTo(1, 1e-6));
      expect(tracker['AA:00:00:00:00:01']!.calibrated, isTrue);
    });

    test('lists nearest first and forgets devices that went quiet', () {
      final tracker = Tracker(const Settings(outOfRangeSeconds: 30));
      tracker.ingest(sight('AA:00:00:00:00:01', at: t0, rssi: -80));
      tracker.ingest(sight('AA:00:00:00:00:02', at: t0.add(const Duration(seconds: 20)), rssi: -50));
      expect(tracker.devices().map((d) => d.address), ['AA:00:00:00:00:02', 'AA:00:00:00:00:01']);
      expect(tracker.prune(t0.add(const Duration(seconds: 31))), ['AA:00:00:00:00:01']);
      expect(tracker.length, 1);
    });

    test('angleFor is stable and within a full turn', () {
      expect(angleFor('AA:00:00:00:00:01'), angleFor('AA:00:00:00:00:01'));
      for (final id in ['', 'a', 'AA:00:00:00:00:01', 'zz' * 40]) {
        expect(angleFor(id), inInclusiveRange(0, 2 * math.pi));
      }
    });
  });

  group('radar scale', () {
    test('grows at once, but shrinks one ring at a time with hysteresis', () {
      expect(nextRange(5, 7), 10);
      expect(nextRange(10, 4.5), 10, reason: '4.5 m is not well inside the 5 m ring');
      expect(nextRange(10, 3), 5);
      expect(nextRange(5, 0.2), 2, reason: 'never below the minimum range');
    });

    test('maps distance onto a log scale', () {
      expect(radiusFor(0, 10, 100), 0);
      expect(radiusFor(10, 10, 100), closeTo(100, 1e-9));
      expect(radiusFor(50, 10, 100), closeTo(100, 1e-9));
      expect(radiusFor(1, 10, 100), greaterThan(10));
    });
  });
}
