import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nearby/src/controller.dart';
import 'package:nearby/src/core/address.dart';
import 'package:nearby/src/core/settings.dart';
import 'package:nearby/src/core/whitelist.dart';
import 'package:nearby/src/scan/scanner.dart';
import 'package:nearby/src/store.dart';

import 'fakes.dart';

const lamp = 'AA:00:00:00:00:01';
const stranger = 'AA:00:00:00:00:02';
const visitor = 'AA:00:00:00:00:03';
const phone = '6E:1B:00:00:00:04';

/// Fails the first [failures] writes, like a full disk that later frees up.
class FlakyStore extends MemoryStore {
  FlakyStore(this.failures);

  int failures;

  @override
  Future<void> write(String name, Object? json) async {
    if (failures > 0) {
      failures -= 1;
      throw const FileSystemException('disk full');
    }
    await super.write(name, json);
  }
}

class Rig {
  Rig(this.async, {Map<String, Object?>? saved, MemoryStore? store}) : store = store ?? MemoryStore(saved);

  final FakeAsync async;
  final MemoryStore store;
  final scanner = FakeScanner();
  final pinger = FakePinger();
  final notifier = FakeNotifier();
  late final controller = NearbyController(
    scanner: scanner,
    pinger: pinger,
    notifier: notifier,
    store: store,
    clock: () => now,
  );

  DateTime get now => t0.add(async.elapsed);

  void start() {
    controller.start();
    async.flushMicrotasks();
  }

  /// Advertisements from [address] every [every] for [times] rounds, letting time pass between them.
  void hear(String address, {int times = 3, Duration every = const Duration(seconds: 1), AddressKind? kind}) {
    for (var i = 0; i < times; i++) {
      scanner.emit(sight(address, at: now, kind: kind ?? AddressKind.public, name: 'Device $address'));
      async.elapse(every);
    }
  }

  void settle() => async.elapse(const Duration(seconds: 3));
}

/// A setup that has finished learning before, with [addresses] whitelisted.
Map<String, Object?> savedWhitelist(List<String> addresses) => {
  whitelistFile: (Whitelist()..addAll(addresses)).toJson(),
  stateFile: {'learned': true},
};

extension on Whitelist {
  void addAll(List<String> addresses) {
    for (final address in addresses) {
      add(address, at: t0);
    }
  }
}

void main() {
  group('review fixes', reviewFixes);

  test('a first run learns what is around, then alerts on newcomers', () {
    fakeAsync((async) {
      final rig = Rig(async)..start();
      expect(rig.controller.learning, isTrue);
      expect(rig.scanner.calls, ['open', 'start']);

      rig.hear(lamp);
      rig.hear(phone, kind: AddressKind.resolvable);
      rig.settle();
      expect(rig.controller.whitelist.contains(lamp), isTrue);
      expect(rig.controller.whitelist.contains(phone), isFalse, reason: 'rotating addresses are not learned');
      expect(rig.store.documents[whitelistFile], [
        {
          'address': lamp,
          'label': null,
          'name': 'Device $lamp',
          'added': rig.controller.whitelist[lamp]!.added.toIso8601String(),
        },
      ]);
      expect(rig.pinger.pings, 0);

      async.elapse(const Duration(minutes: 2));
      expect(rig.controller.learning, isFalse);
      rig.hear(lamp);
      rig.hear(stranger);
      rig.settle();
      expect(rig.pinger.pings, 1);
      expect(rig.notifier.shown.single.summary, 'New device nearby');
      expect(rig.controller.arrivals.single.device.address, stranger);

      rig.notifier.press(1, 'whitelist');
      async.elapse(const Duration(seconds: 1));
      expect(rig.controller.whitelist.contains(stranger), isTrue);
      expect((rig.store.documents[whitelistFile] as List).length, 2);
      rig.controller.dispose();
    });
  });

  test('arrivals close together share one ping and one notification', () {
    fakeAsync((async) {
      final rig = Rig(async, saved: savedWhitelist([lamp]))..start();
      expect(rig.controller.learning, isFalse, reason: 'a saved whitelist means this is not a first run');
      for (var i = 0; i < 2; i++) {
        rig.scanner.emit(sight(stranger, at: rig.now));
        rig.scanner.emit(sight(visitor, at: rig.now));
        async.elapse(const Duration(milliseconds: 300));
      }
      rig.settle();
      expect(rig.pinger.pings, 1);
      expect(rig.notifier.shown.single.summary, '2 new devices nearby');
      expect(rig.controller.arrivals.map((a) => a.device.address).toSet(), {stranger, visitor});
      rig.controller.dispose();
    });
  });

  test('alerts are spaced out, and arrivals in between join the next one', () {
    fakeAsync((async) {
      final rig = Rig(async, saved: savedWhitelist([]))..start();
      rig.hear(stranger);
      rig.settle();
      expect(rig.pinger.pings, 1);
      // Two more arrive shortly after the first alert: they wait for the gap, then share one alert.
      rig.hear(visitor);
      rig.hear(lamp);
      expect(rig.pinger.pings, 1);
      async.elapse(alertGap);
      expect(rig.pinger.pings, 2);
      expect(rig.notifier.shown.map((n) => n.summary), ['New device nearby', '2 new devices nearby']);
      expect(rig.controller.arrivals, hasLength(3));
      rig.controller.dispose();
    });
  });

  test('the whitelist button only applies to its own notification', () {
    fakeAsync((async) {
      final rig = Rig(async, saved: savedWhitelist([]))..start();
      rig.hear(stranger);
      rig.settle();
      rig.notifier.press(99, 'whitelist');
      rig.notifier.press(1, 'default');
      async.elapse(const Duration(seconds: 1));
      expect(rig.controller.whitelist.contains(stranger), isFalse);
      rig.controller.dispose();
    });
  });

  test('with ping and notification off, arrivals are only logged', () {
    fakeAsync((async) {
      final rig = Rig(
        async,
        saved: {...savedWhitelist([]), settingsFile: const Settings(ping: false, notify: false).toJson()},
      )..start();
      rig.hear(stranger);
      rig.settle();
      expect(rig.pinger.pings, 0);
      expect(rig.notifier.shown, isEmpty);
      expect(rig.controller.arrivals, hasLength(1));
      rig.controller.dispose();
    });
  });

  test('a device whitelisted while its alert is pending is not announced', () {
    fakeAsync((async) {
      final rig = Rig(async, saved: savedWhitelist([]))..start();
      rig.hear(stranger, times: 2, every: const Duration(milliseconds: 200));
      rig.controller.setWhitelisted(stranger, true);
      rig.settle();
      expect(rig.pinger.pings, 0);
      expect(rig.controller.arrivals, isEmpty);
      rig.controller.dispose();
    });
  });

  test('pausing stops discovery and resuming restarts it', () {
    fakeAsync((async) {
      final rig = Rig(async, saved: savedWhitelist([]))..start();
      rig.controller.pause();
      async.flushMicrotasks();
      expect(rig.scanner.discovering, isFalse);
      rig.controller.resume();
      async.flushMicrotasks();
      expect(rig.scanner.discovering, isTrue);
      expect(rig.scanner.calls, ['open', 'start', 'stop', 'start']);
      rig.controller.dispose();
    });
  });

  test('a duty cycle scans, rests, and scans again', () {
    fakeAsync((async) {
      final rig = Rig(
        async,
        saved: {...savedWhitelist([]), settingsFile: const Settings(scanOnSeconds: 10, scanOffSeconds: 20).toJson()},
      )..start();
      expect(rig.scanner.discovering, isTrue);
      async.elapse(const Duration(seconds: 10));
      expect(rig.scanner.discovering, isFalse);
      expect(rig.controller.resting, isTrue);
      async.elapse(const Duration(seconds: 20));
      expect(rig.scanner.discovering, isTrue);
      expect(rig.controller.resting, isFalse);
      expect(rig.scanner.calls, ['open', 'start', 'stop', 'start']);
      rig.controller.dispose();
    });
  });

  test('a device resting through a duty cycle does not arrive again', () {
    fakeAsync((async) {
      final rig = Rig(
        async,
        saved: {
          ...savedWhitelist([]),
          settingsFile: const Settings(
            scanOnSeconds: 10,
            scanOffSeconds: 60,
            outOfRangeSeconds: 10,
            reAlertMinutes: 1,
          ).toJson(),
        },
      )..start();
      rig.hear(stranger);
      rig.settle();
      expect(rig.pinger.pings, 1);
      // Rest for 60 s, longer than both the out-of-range time and the quiet period.
      async.elapse(const Duration(seconds: 65));
      rig.hear(stranger);
      rig.settle();
      expect(rig.pinger.pings, 1);
      rig.controller.dispose();
    });
  });

  test('quitting a first run before anything was learned saves nothing', () {
    fakeAsync((async) {
      final rig = Rig(async)..start();
      async.elapse(const Duration(seconds: 5));
      rig.controller.dispose();
      async.flushMicrotasks();
      expect(rig.store.documents, isEmpty);
      expect(rig.scanner.calls.last, 'close');
    });
  });

  test('whitelist all in range skips rotating addresses', () {
    fakeAsync((async) {
      final rig = Rig(async, saved: savedWhitelist([]))..start();
      rig.hear(stranger, times: 1);
      rig.hear(phone, times: 1, kind: AddressKind.resolvable);
      async.elapse(const Duration(seconds: 1));
      expect(rig.controller.whitelistAllInRange(), 1);
      expect(rig.controller.whitelist.contains(stranger), isTrue);
      expect(rig.controller.whitelist.contains(phone), isFalse);
      rig.controller.dispose();
    });
  });

  test('calibrating takes the current smoothed signal as the 1 m reference', () {
    fakeAsync((async) {
      final rig = Rig(async, saved: savedWhitelist([]))..start();
      rig.hear(lamp, times: 1);
      async.elapse(const Duration(seconds: 1));
      rig.controller.calibrate(lamp);
      async.elapse(const Duration(seconds: 1));
      expect(rig.controller.settings.calibrations, {lamp: -60});
      expect(rig.controller.devices.single.distance, closeTo(1, 1e-6));
      rig.controller.clearCalibration(lamp);
      expect(rig.controller.settings.calibrations, isEmpty);
      rig.controller.dispose();
    });
  });
}

void reviewFixes() {
  test('first-run learning waits until scanning actually starts', () {
    fakeAsync((async) {
      final rig = Rig(async);
      rig.scanner.startAs = ScannerStatus.poweredOff;
      rig.start();
      expect(rig.controller.learningPending, isTrue);
      async.elapse(const Duration(minutes: 5));
      expect(rig.controller.learning, isFalse, reason: 'nothing to learn while Bluetooth is off');
      rig.scanner.powerOn();
      expect(rig.controller.learning, isTrue);
      rig.hear(lamp);
      async.elapse(const Duration(minutes: 2));
      expect(rig.controller.learning, isFalse);
      expect(rig.controller.whitelist.contains(lamp), isTrue);
      expect(rig.store.documents[stateFile], {'learned': true});
      rig.controller.dispose();
    });
  });

  test('a learning session that found nothing still ends first-run learning', () {
    fakeAsync((async) {
      final first = Rig(async)..start();
      async.elapse(const Duration(minutes: 3));
      first.controller.dispose();
      async.flushMicrotasks();
      expect(first.store.documents[stateFile], {'learned': true});

      final second = Rig(async, store: first.store)..start();
      expect(second.controller.learning, isFalse);
      expect(second.controller.learningPending, isFalse);
      second.controller.dispose();
    });
  });

  test('changing a setting during first-run learning does not skip learning next time', () {
    fakeAsync((async) {
      final first = Rig(async)..start();
      first.controller.updateSettings(first.controller.settings.copyWith(ping: false));
      async.elapse(const Duration(seconds: 5));
      first.controller.dispose();
      async.flushMicrotasks();
      expect(first.store.documents[stateFile], {'learned': false});

      final second = Rig(async, store: first.store)..start();
      expect(second.controller.learning, isTrue);
      second.controller.dispose();
    });
  });

  test('an alert waiting to go out is dropped when learning starts or scanning pauses', () {
    fakeAsync((async) {
      final rig = Rig(async, saved: savedWhitelist([]))..start();
      rig.hear(stranger, times: 2, every: const Duration(milliseconds: 100));
      rig.controller.startLearning();
      rig.settle();
      expect(rig.pinger.pings, 0);
      expect(rig.notifier.shown, isEmpty);

      rig.controller.stopLearning();
      rig.hear(visitor, times: 2, every: const Duration(milliseconds: 100));
      rig.controller.pause();
      rig.settle();
      expect(rig.pinger.pings, 0);
      expect(rig.controller.arrivals, isEmpty);
      rig.controller.dispose();
    });
  });

  test('the notification button never whitelists a rotating address', () {
    fakeAsync((async) {
      final rig = Rig(async, saved: {...savedWhitelist([]), settingsFile: const Settings(alertRotating: true).toJson()})
        ..start();
      rig.scanner.emit(sight(phone, at: rig.now, kind: AddressKind.resolvable));
      rig.scanner.emit(sight(stranger, at: rig.now));
      async.elapse(const Duration(milliseconds: 300));
      rig.scanner.emit(sight(phone, at: rig.now, kind: AddressKind.resolvable));
      rig.scanner.emit(sight(stranger, at: rig.now));
      rig.settle();
      expect(rig.notifier.shown.single.actions, {'whitelist': 'Whitelist 1'});
      rig.notifier.press(1, 'whitelist');
      async.elapse(const Duration(seconds: 1));
      expect(rig.controller.whitelist.contains(stranger), isTrue);
      expect(rig.controller.whitelist.contains(phone), isFalse);
      rig.controller.dispose();
    });
  });

  test('a dismissed notification forgets its devices', () {
    fakeAsync((async) {
      final rig = Rig(async, saved: savedWhitelist([]))..start();
      rig.hear(stranger);
      rig.settle();
      rig.notifier.dismiss(1);
      rig.notifier.press(1, 'whitelist');
      async.elapse(const Duration(seconds: 1));
      expect(rig.controller.whitelist.contains(stranger), isFalse);
      rig.controller.dispose();
    });
  });

  test('settings changes in quick succession leave a single duty cycle running', () {
    fakeAsync((async) {
      final rig = Rig(
        async,
        saved: {...savedWhitelist([]), settingsFile: const Settings(scanOnSeconds: 10, scanOffSeconds: 20).toJson()},
      )..start();
      rig.controller.updateSettings(rig.controller.settings.copyWith(scanOnSeconds: 15));
      rig.controller.updateSettings(rig.controller.settings.copyWith(scanOnSeconds: 20));
      async.elapse(const Duration(seconds: 21));
      expect(rig.scanner.calls.where((call) => call == 'stop'), hasLength(1));
      rig.controller.dispose();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('disposing while still starting leaves nothing running', () {
    fakeAsync((async) {
      // While settings load…
      final loading = Rig(async);
      unawaited(loading.controller.start());
      loading.controller.dispose();
      async.flushMicrotasks();
      expect(loading.scanner.calls, isNot(contains('open')));

      // …and while the scanner opens.
      final opening = Rig(async);
      opening.scanner.holdOpen = Completer();
      unawaited(opening.controller.start());
      async.flushMicrotasks();
      opening.controller.dispose();
      opening.scanner.holdOpen!.complete();
      async.flushMicrotasks();
      expect(opening.scanner.calls, ['open', 'close']);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('shutdown writes pending changes at once', () {
    fakeAsync((async) {
      final rig = Rig(async, saved: savedWhitelist([]))..start();
      rig.controller.setWhitelisted(lamp, true);
      unawaited(rig.controller.shutdown());
      async.flushMicrotasks();
      expect((rig.store.documents[whitelistFile] as List).single, containsPair('address', lamp));
      expect(rig.scanner.calls.last, 'close');
    });
  });

  test('a failed save is retried', () {
    fakeAsync((async) {
      final store = FlakyStore(1)..documents.addAll(savedWhitelist([]));
      final rig = Rig(async, store: store)..start();
      rig.controller.setWhitelisted(lamp, true);
      async.elapse(const Duration(seconds: 1));
      expect((store.documents[whitelistFile] as List), isEmpty, reason: 'the first write failed');
      async.elapse(const Duration(seconds: 10));
      expect((store.documents[whitelistFile] as List).single, containsPair('address', lamp));
      rig.controller.dispose();
    });
  });
}
