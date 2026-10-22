import 'dart:async';

import 'package:nearby/src/alert/notifier.dart';
import 'package:nearby/src/alert/pinger.dart';
import 'package:nearby/src/core/address.dart';
import 'package:nearby/src/core/sighting.dart';
import 'package:nearby/src/core/tracker.dart';
import 'package:nearby/src/scan/scanner.dart';

final t0 = DateTime.utc(2026, 10, 20, 12);

Sighting sight(
  String address, {
  required DateTime at,
  AddressKind kind = AddressKind.public,
  int rssi = -60,
  String? name,
}) => Sighting(address: address, kind: kind, rssi: rssi, at: at, name: name);

TrackedDevice tracked(String address, {AddressKind kind = AddressKind.public, double distance = 2, String? name}) =>
    TrackedDevice(
      address: address,
      kind: kind,
      name: name,
      rssi: -60,
      smoothed: -60,
      ref1m: -59,
      distance: distance,
      calibrated: false,
      firstSeen: t0,
      lastSeen: t0,
      count: 1,
      angle: 0,
    );

class FakeScanner implements Scanner {
  final _sightings = StreamController<Sighting>.broadcast(sync: true);
  final _states = StreamController<ScannerState>.broadcast(sync: true);
  final calls = <String>[];

  @override
  var state = const ScannerState(ScannerStatus.idle, adapter: 'test');

  bool get discovering => state.status == ScannerStatus.scanning;

  @override
  Stream<Sighting> get sightings => _sightings.stream;

  @override
  Stream<ScannerState> get states => _states.stream;

  void emit(Sighting sighting) {
    if (discovering) _sightings.add(sighting);
  }

  void _set(ScannerStatus status) {
    state = ScannerState(status, adapter: 'test');
    _states.add(state);
  }

  void powerOff() => _set(ScannerStatus.poweredOff);

  /// The user declined the scanning permission.
  void deny() => _set(ScannerStatus.noPermission);

  /// Bluetooth came back on; a scanner that was asked to scan resumes.
  void powerOn() => _set(wanted ? ScannerStatus.scanning : ScannerStatus.idle);

  /// Whether discovery was last requested (rather than stopped), whatever the adapter is doing.
  var wanted = false;

  /// Start the next startDiscovery() in this state instead of scanning.
  ScannerStatus? startAs;

  /// While set, open() waits for it.
  Completer<void>? holdOpen;

  @override
  Future<void> open() async {
    calls.add('open');
    await holdOpen?.future;
  }

  @override
  Future<void> startDiscovery({required bool classic}) async {
    calls.add(classic ? 'start classic' : 'start');
    wanted = true;
    _set(startAs ?? ScannerStatus.scanning);
  }

  @override
  Future<void> stopDiscovery() async {
    calls.add('stop');
    wanted = false;
    if (state.status == ScannerStatus.scanning) _set(ScannerStatus.idle);
  }

  @override
  Future<void> requestAccess() async => calls.add('request access');

  @override
  Future<void> close() async => calls.add('close');
}

class FakePinger implements Pinger {
  var pings = 0;

  @override
  Future<bool> ping() async {
    pings += 1;
    return true;
  }
}

class FakeNotifier implements Notifier {
  final shown = <Notice>[];
  final _actions = StreamController<NoticeAction>.broadcast(sync: true);
  final _closed = StreamController<int>.broadcast(sync: true);

  @override
  Stream<NoticeAction> get actions => _actions.stream;

  @override
  Stream<int> get closed => _closed.stream;

  /// Presses [key] on the notice with [id] (1-based, in the order shown).
  void press(int id, String key) => _actions.add(NoticeAction(id, key));

  /// The notice with [id] expired or was dismissed.
  void dismiss(int id) => _closed.add(id);

  @override
  Future<int?> show(Notice notice) async {
    shown.add(notice);
    return shown.length;
  }

  /// Whether the user lets the app show notifications; [requestAccess] turns them on.
  var permitted = true;
  var requests = 0;

  @override
  Future<bool> allowed() async => permitted;

  @override
  Future<void> requestAccess() async {
    requests += 1;
    permitted = true;
  }

  @override
  Future<void> close() async {}
}
