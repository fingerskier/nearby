import 'dart:async';

import 'package:flutter/foundation.dart';

import 'alert/notifier.dart';
import 'alert/pinger.dart';
import 'core/format.dart';
import 'core/guard.dart';
import 'core/settings.dart';
import 'core/sighting.dart';
import 'core/tracker.dart';
import 'core/whitelist.dart';
import 'scan/scanner.dart';
import 'store.dart';

/// An unlisted device that came into range.
class ArrivalRecord {
  const ArrivalRecord(this.device, this.at);

  final TrackedDevice device;
  final DateTime at;
}

const settingsFile = 'settings.json';
const whitelistFile = 'whitelist.json';

/// Arrivals this close together share one ping and one notification.
const _batchWindow = Duration(milliseconds: 1500);

/// At most one ping and notification this often; arrivals in between join the next one.
const alertGap = Duration(seconds: 10);
const _tickEvery = Duration(milliseconds: 500);
const _saveAfter = Duration(milliseconds: 500);
const _arrivalLog = 100;

/// Runs the scanner, ranges what it hears, keeps the whitelist, and raises alerts.
class NearbyController extends ChangeNotifier {
  NearbyController({
    required this.scanner,
    required this.pinger,
    required this.notifier,
    required this.store,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Scanner scanner;
  final Pinger pinger;
  final Notifier notifier;
  final Store store;
  final DateTime Function() _clock;

  var _settings = const Settings();
  var _whitelist = Whitelist();
  late Tracker _tracker = Tracker(_settings);
  late Guard _guard = Guard(_settings, _whitelist);
  var _devices = const <TrackedDevice>[];
  final _arrivals = <ArrivalRecord>[];
  final _pending = <TrackedDevice>[];
  final _noticeTargets = <int, List<String>>{};
  final _subscriptions = <StreamSubscription<Object?>>[];
  late DateTime _now = _clock();
  var _ready = false;
  var _paused = false;
  var _resting = false;
  var _disposed = false;
  Timer? _ticker;
  Timer? _cycle;
  Timer? _flushTimer;
  Timer? _saveTimer;
  DateTime? _lastAlertAt;
  var _dirty = false;

  bool get ready => _ready;
  Settings get settings => _settings;
  Whitelist get whitelist => _whitelist;

  /// Devices in range, nearest first, as of the last tick.
  List<TrackedDevice> get devices => _devices;

  /// Newest first.
  List<ArrivalRecord> get arrivals => List.unmodifiable(_arrivals);
  ScannerState get scannerState => scanner.state;
  DateTime get now => _now;
  bool get paused => _paused;

  /// Between scans in a duty cycle.
  bool get resting => _resting;
  bool get learning => _guard.isLearning(_now);

  Duration get learnLeft => learning ? _guard.learnUntil!.difference(_now) : Duration.zero;

  /// Loads settings and the whitelist, then starts scanning. A first run (no whitelist saved yet)
  /// starts in learning mode, so whatever is already around doesn't set off alerts.
  Future<void> start() async {
    _settings = Settings.fromJson(await store.read(settingsFile));
    final savedWhitelist = await store.read(whitelistFile);
    _whitelist = Whitelist.fromJson(savedWhitelist);
    _tracker = Tracker(_settings);
    _guard = Guard(_settings, _whitelist);
    _now = _clock();
    if (savedWhitelist == null) _guard.startLearning(_now);
    _subscriptions
      ..add(scanner.sightings.listen(_onSighting))
      ..add(scanner.states.listen((_) => notifyListeners()))
      ..add(notifier.actions.listen(_onNoticeAction, onError: (Object _) {}));
    await scanner.open();
    _ticker = Timer.periodic(_tickEvery, (_) => _tick());
    _ready = true;
    await _applyScanning();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in [_ticker, _cycle, _flushTimer, _saveTimer]) {
      timer?.cancel();
    }
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_save());
    unawaited(scanner.close());
    unawaited(notifier.close());
    super.dispose();
  }

  void pause() {
    _paused = true;
    unawaited(_applyScanning());
    notifyListeners();
  }

  void resume() {
    _paused = false;
    unawaited(_applyScanning());
    notifyListeners();
  }

  void startLearning() {
    _guard.startLearning(_now);
    notifyListeners();
  }

  void stopLearning() {
    _guard.stopLearning();
    notifyListeners();
  }

  void updateSettings(Settings next) {
    final rescan =
        next.includeClassic != _settings.includeClassic ||
        next.scanOnSeconds != _settings.scanOnSeconds ||
        next.scanOffSeconds != _settings.scanOffSeconds;
    _settings = next;
    _tracker.configure(next);
    _guard.settings = next;
    _saveSoon();
    if (rescan) unawaited(_applyScanning());
    notifyListeners();
  }

  void setWhitelisted(String address, bool listed) {
    final changed = listed
        ? _whitelist.add(address, name: _tracker[address]?.name, at: _clock())
        : _whitelist.remove(address);
    if (!changed) return;
    _saveSoon();
    notifyListeners();
  }

  void renameWhitelisted(String address, String? label) {
    _whitelist.rename(address, label);
    _saveSoon();
    notifyListeners();
  }

  /// Whitelists every device in range whose address is stable; returns how many were added.
  int whitelistAllInRange() {
    var added = 0;
    for (final device in _devices) {
      if (device.kind.isStable && _whitelist.add(device.address, name: device.name, at: _clock())) added += 1;
    }
    if (added > 0) {
      _saveSoon();
      notifyListeners();
    }
    return added;
  }

  /// Takes the device's current smoothed RSSI as its 1 m reference.
  void calibrate(String address) {
    final device = _tracker[address];
    if (device == null) return;
    updateSettings(
      _settings.copyWith(calibrations: {..._settings.calibrations, address: device.smoothed.roundToDouble()}),
    );
  }

  void clearCalibration(String address) {
    updateSettings(_settings.copyWith(calibrations: {..._settings.calibrations}..remove(address)));
  }

  void clearArrivals() {
    _arrivals.clear();
    notifyListeners();
  }

  /// Plays the ping and shows a sample notification, so the user can check both work.
  Future<({bool ping, bool notify})> testAlert() async {
    final pinged = await pinger.ping();
    final shown = await notifier.show(
      const Notice(
        summary: 'nearby: test alert',
        body: 'This is how an unlisted device coming into range is announced.',
      ),
    );
    return (ping: pinged, notify: shown != null);
  }

  void _onSighting(Sighting sighting) {
    final device = _tracker.ingest(sighting);
    switch (_guard.observe(device, sighting.at)) {
      case Learned():
        _saveSoon();
      case Arrived(:final device):
        _pending.add(device);
        _scheduleFlush();
      case null:
        break;
    }
  }

  void _scheduleFlush() {
    if (_flushTimer != null) return;
    var wait = _batchWindow;
    final last = _lastAlertAt;
    if (last != null) {
      final gapLeft = alertGap - _clock().difference(last);
      if (gapLeft > wait) wait = gapLeft;
    }
    _flushTimer = Timer(wait, () => unawaited(_flush()));
  }

  Future<void> _flush() async {
    _flushTimer = null;
    // Keep only the latest state of each device, and skip any whitelisted while the batch waited.
    final batch = {for (final device in _pending) device.address: device};
    _pending.clear();
    batch.removeWhere((address, _) => _whitelist.contains(address));
    if (batch.isEmpty || _disposed) return;
    final at = _lastAlertAt = _clock();
    _arrivals.insertAll(0, batch.values.map((device) => ArrivalRecord(device, at)));
    if (_arrivals.length > _arrivalLog) _arrivals.removeRange(_arrivalLog, _arrivals.length);
    notifyListeners();
    if (_settings.ping) unawaited(pinger.ping());
    if (_settings.notify) {
      final id = await notifier.show(noticeFor(batch.values.toList()));
      if (id != null) _noticeTargets[id] = batch.keys.toList();
    }
  }

  void _onNoticeAction(NoticeAction action) {
    final targets = _noticeTargets.remove(action.id);
    if (targets == null || action.key != 'whitelist') return;
    for (final address in targets) {
      _whitelist.add(address, name: _tracker[address]?.name, at: _clock());
    }
    _saveSoon();
    notifyListeners();
  }

  void _tick() {
    _now = _clock();
    _tracker.prune(_now);
    _guard.prune(_now);
    _devices = _tracker.devices();
    notifyListeners();
  }

  /// Starts or stops discovery to match pause and the duty cycle.
  Future<void> _applyScanning() async {
    _cycle?.cancel();
    _resting = false;
    if (_disposed) return;
    if (_paused) return scanner.stopDiscovery();
    await scanner.startDiscovery(classic: _settings.includeClassic);
    if (_settings.continuous || _disposed) return;
    _cycle = Timer(Duration(seconds: _settings.scanOnSeconds), () {
      _resting = true;
      unawaited(scanner.stopDiscovery());
      _cycle = Timer(Duration(seconds: _settings.scanOffSeconds), () => unawaited(_applyScanning()));
      notifyListeners();
    });
  }

  void _saveSoon() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveAfter, () => unawaited(_save()));
  }

  /// Writes settings and whitelist if anything changed. A first run quit before anything was learned
  /// leaves no whitelist behind, so the next start learns again.
  Future<void> _save() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_dirty) return;
    _dirty = false;
    await store.write(settingsFile, _settings.toJson());
    await store.write(whitelistFile, _whitelist.toJson());
  }
}

/// One notification for a batch of arrivals.
Notice noticeFor(List<TrackedDevice> devices) {
  String line(TrackedDevice device) => [
    deviceLabel(name: device.name, manufacturer: device.manufacturer),
    '≈ ${formatDistance(device.distance)}',
    device.address,
  ].join(' · ');
  if (devices.length == 1) {
    return Notice(summary: 'New device nearby', body: line(devices.single), actions: const {'whitelist': 'Whitelist'});
  }
  return Notice(
    summary: '${devices.length} new devices nearby',
    body: devices.map(line).join('\n'),
    actions: const {'whitelist': 'Whitelist all'},
  );
}
