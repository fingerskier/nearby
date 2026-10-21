import 'package:flutter_test/flutter_test.dart';
import 'package:nearby/src/core/address.dart';
import 'package:nearby/src/core/guard.dart';
import 'package:nearby/src/core/settings.dart';
import 'package:nearby/src/core/tracker.dart';
import 'package:nearby/src/core/whitelist.dart';

import '../fakes.dart';

const lamp = 'AA:00:00:00:00:01';
const stranger = 'AA:00:00:00:00:02';

void main() {
  late Whitelist whitelist;
  late Guard guard;

  setUp(() {
    whitelist = Whitelist();
    guard = Guard(const Settings(outOfRangeSeconds: 60, reAlertMinutes: 30), whitelist);
  });

  /// Observes [device] at each offset (seconds after t0) and returns the events.
  List<GuardEvent?> observe(TrackedDevice device, List<int> seconds) => [
    for (final s in seconds) guard.observe(device, t0.add(Duration(seconds: s))),
  ];

  test('alerts once an unlisted device is seen twice, and once per visit', () {
    final events = observe(tracked(stranger), [0, 1, 2, 3]);
    expect(events[0], isNull, reason: 'a single packet could be a fluke');
    expect(events[1], isA<Arrived>());
    expect(events.skip(2), everyElement(isNull));
  });

  test('stays quiet for whitelisted devices', () {
    whitelist.add(lamp, at: t0);
    expect(observe(tracked(lamp), [0, 1, 2]), everyElement(isNull));
  });

  test('a device that left and came back after the quiet period alerts again', () {
    expect(observe(tracked(stranger), [0, 1]).last, isA<Arrived>());
    // Back after 10 minutes: a new visit, but still inside the 30 minute quiet period.
    expect(observe(tracked(stranger), [600, 601]), everyElement(isNull));
    // Back after 40 minutes.
    expect(observe(tracked(stranger), [2400, 2401]).last, isA<Arrived>());
  });

  test('a short gap is the same visit', () {
    expect(observe(tracked(stranger), [0, 1]).last, isA<Arrived>());
    guard.settings = const Settings(outOfRangeSeconds: 60, reAlertMinutes: 1);
    expect(observe(tracked(stranger), [50, 51, 100]), everyElement(isNull));
  });

  test('ignores rotating addresses unless asked to alert on them', () {
    final phone = tracked(stranger, kind: AddressKind.resolvable);
    expect(observe(phone, [0, 1, 2]), everyElement(isNull));
    guard = Guard(const Settings(alertRotating: true), whitelist);
    expect(observe(phone, [0, 1]).last, isA<Arrived>());
  });

  test('with an alert radius, alerts when the device comes within it', () {
    guard.settings = const Settings(alertRadius: 3);
    expect(guard.observe(tracked(stranger, distance: 8), t0), isNull);
    expect(guard.observe(tracked(stranger, distance: 8), t0.add(const Duration(seconds: 1))), isNull);
    expect(guard.observe(tracked(stranger, distance: 2.5), t0.add(const Duration(seconds: 2))), isA<Arrived>());
  });

  group('learning', () {
    test('whitelists stable devices it confirms, and skips rotating ones', () {
      guard.startLearning(t0);
      expect(guard.isLearning(t0), isTrue);
      final events = observe(tracked(lamp, name: 'Lamp'), [0, 1, 2]);
      expect(events[1], isA<Learned>());
      expect(events[2], isNull, reason: 'already listed');
      expect(whitelist[lamp]!.name, 'Lamp');
      observe(tracked(stranger, kind: AddressKind.resolvable), [0, 1]);
      expect(whitelist.contains(stranger), isFalse);
    });

    test('ends after the configured time, then guards', () {
      guard.settings = const Settings(learnMinutes: 2);
      guard.startLearning(t0);
      expect(guard.isLearning(t0.add(const Duration(minutes: 2))), isFalse);
      expect(observe(tracked(stranger), [150, 151]).last, isA<Arrived>());
    });

    test('can be stopped early', () {
      guard.startLearning(t0);
      guard.stopLearning();
      expect(guard.isLearning(t0), isFalse);
      expect(observe(tracked(stranger), [0, 1]).last, isA<Arrived>());
    });
  });

  test('prune keeps quiet periods that are still running', () {
    expect(observe(tracked(stranger), [0, 1]).last, isA<Arrived>());
    guard.prune(t0.add(const Duration(minutes: 5)));
    expect(observe(tracked(stranger), [600, 601]), everyElement(isNull));
  });
}
