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

/// Remembers whether a learning session has ever finished, so first-run learning happens exactly once.
const stateFile = 'state.json';

/// Arrivals this close together share one ping and one notification.
const _batchWindow = Duration(milliseconds: 1500);

/// At most one ping and notification this often; arrivals in between join the next one.
const alertGap = Duration(seconds: 10);
const _tickEvery = Duration(milliseconds: 500);
const _saveAfter = Duration(milliseconds: 500);
const _saveRetryAfter = Duration(seconds: 10);
const _arrivalLog = 100;

/// Notifications whose buttons are still remembered; older ones are long gone from any screen.
const _openNotices = 20;

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
  var _learnedOnce = false;
  var _learnWhenScanning = false;
  var _wasLearning = false;
  var _scanGeneration = 0;
  var _notificationsBlocked = false;
  var _dirty = false;
  Timer? _ticker;
  Timer? _cycle;
  Timer? _flushTimer;
  Timer? _saveTimer;
  DateTime? _lastAlertAt;
  Future<void> _saving = Future.value();
  Future<void>? _shutdown;

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

  /// The user turned this app's notifications off, so arrivals can only ping.
  bool get notificationsBlocked => _notificationsBlocked;

  /// First-run learning is waiting for the scanner to start.
  bool get learningPending => _learnWhenScanning;

  Duration get learnLeft => learning ? _guard.learnUntil!.difference(_now) : Duration.zero;

  /// Loads settings and the whitelist, then starts scanning. Until a learning session has finished once,
  /// the app learns as soon as scanning starts, so whatever is already around doesn't set off alerts.
  Future<void> start() async {
    _settings = Settings.fromJson(await store.read(settingsFile));
    _whitelist = Whitelist.fromJson(await store.read(whitelistFile));
    final state = await store.read(stateFile);
    if (_disposed) return;
    _learnedOnce = (state is Map && state['learned'] == true) || _whitelist.length > 0;
    _learnWhenScanning = !_learnedOnce;
    _tracker = Tracker(_settings);
    _guard = Guard(_settings, _whitelist);
    _now = _clock();
    _subscriptions
      ..add(scanner.sightings.listen(_onSighting))
      ..add(scanner.states.listen((_) => _onScannerState()))
      ..add(notifier.actions.listen(_onNoticeAction, onError: (Object _) {}))
      ..add(notifier.closed.listen(_noticeTargets.remove, onError: (Object _) {}));
    await scanner.open();
    if (_disposed) return;
    // After open, which on Android has asked for the notification permission too.
    await checkNotifications();
    if (_disposed) return;
    _ticker = Timer.periodic(_tickEvery, (_) => _tick());
    _ready = true;
    await _applyScanning();
    _changed();
  }

  /// Stops scanning and timers and writes anything unsaved. Safe to call more than once; [dispose] calls it.
  Future<void> shutdown() => _shutdown ??= _close();

  Future<void> _close() async {
    _disposed = true;
    _scanGeneration += 1;
    for (final timer in [_ticker, _cycle, _flushTimer, _saveTimer]) {
      timer?.cancel();
    }
    // Cancelling takes effect at once; nothing waits for the bus to drop its match rules.
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    await _save();
    await scanner.close();
    await notifier.close();
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }

  void pause() {
    _paused = true;
    _dropPending();
    unawaited(_applyScanning());
    _changed();
  }

  void resume() {
    _paused = false;
    unawaited(_applyScanning());
    _changed();
  }

  /// Asks the user for whatever the scanner is missing, such as Android's Nearby devices permission.
  Future<void> requestScannerAccess() => scanner.requestAccess();

  /// Rereads whether notifications are allowed, e.g. when the user comes back from the system settings.
  Future<void> checkNotifications() async {
    final blocked = !await notifier.allowed();
    if (blocked == _notificationsBlocked) return;
    _notificationsBlocked = blocked;
    _changed();
  }

  Future<void> requestNotifications() async {
    await notifier.requestAccess();
    await checkNotifications();
  }

  void startLearning() {
    _learnWhenScanning = false;
    _guard.startLearning(_now);
    _wasLearning = true;
    // Whatever was about to be announced is about to be learned instead.
    _dropPending();
    _changed();
  }

  void stopLearning() {
    _learnWhenScanning = false;
    _guard.stopLearning();
    _finishLearning();
    _changed();
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
    _changed();
  }

  void setWhitelisted(String address, bool listed) {
    final changed = listed
        ? _whitelist.add(address, name: _tracker[address]?.name, at: _clock())
        : _whitelist.remove(address);
    if (!changed) return;
    _saveSoon();
    _changed();
  }

  void renameWhitelisted(String address, String? label) {
    _whitelist.rename(address, label);
    _saveSoon();
    _changed();
  }

  /// Whitelists every device in range whose address is stable; returns how many were added.
  int whitelistAllInRange() {
    var added = 0;
    for (final device in _devices) {
      if (device.kind.isStable && _whitelist.add(device.address, name: device.name, at: _clock())) added += 1;
    }
    if (added > 0) {
      _saveSoon();
      _changed();
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
    _changed();
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

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _onScannerState() {
    if (_learnWhenScanning && scanner.state.status == ScannerStatus.scanning) startLearning();
    _changed();
  }

  void _finishLearning() {
    _wasLearning = false;
    if (_learnedOnce) return;
    _learnedOnce = true;
    _saveSoon();
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

  void _dropPending() {
    _pending.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
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
    if (batch.isEmpty || _disposed || _paused || _guard.isLearning(_clock())) return;
    final at = _lastAlertAt = _clock();
    _arrivals.insertAll(0, batch.values.map((device) => ArrivalRecord(device, at)));
    if (_arrivals.length > _arrivalLog) _arrivals.removeRange(_arrivalLog, _arrivals.length);
    _changed();
    if (_settings.ping) unawaited(pinger.ping());
    if (_settings.notify) {
      final id = await notifier.show(noticeFor(batch.values.toList()));
      if (id == null) return;
      // Only fixed addresses can be whitelisted; a rotating one would never match again.
      _noticeTargets[id] = [
        for (final device in batch.values)
          if (device.kind.isStable) device.address,
      ];
      while (_noticeTargets.length > _openNotices) {
        _noticeTargets.remove(_noticeTargets.keys.first);
      }
    }
  }

  void _onNoticeAction(NoticeAction action) {
    final targets = _noticeTargets.remove(action.id);
    if (targets == null || action.key != 'whitelist') return;
    for (final address in targets) {
      _whitelist.add(address, name: _tracker[address]?.name, at: _clock());
    }
    _saveSoon();
    _changed();
  }

  void _tick() {
    _now = _clock();
    _tracker.prune(_now);
    _guard.prune(_now);
    _devices = _tracker.devices();
    final learningNow = learning;
    if (_wasLearning && !learningNow) _finishLearning();
    _wasLearning = learningNow;
    _changed();
  }

  /// Starts or stops discovery to match pause and the duty cycle. A newer call supersedes an older one
  /// still waiting on the scanner, so overlapping calls never leave a stray cycle timer behind.
  Future<void> _applyScanning() async {
    final generation = ++_scanGeneration;
    _cycle?.cancel();
    _cycle = null;
    _resting = false;
    if (_disposed) return;
    if (_paused) return scanner.stopDiscovery();
    await scanner.startDiscovery(classic: _settings.includeClassic);
    if (generation != _scanGeneration || _settings.continuous) return;
    _cycle = Timer(Duration(seconds: _settings.scanOnSeconds), () {
      _resting = true;
      unawaited(scanner.stopDiscovery());
      _cycle = Timer(Duration(seconds: _settings.scanOffSeconds), () => unawaited(_applyScanning()));
      _changed();
    });
  }

  void _saveSoon() {
    _dirty = true;
    _saveTimer?.cancel();
    if (!_disposed) _saveTimer = Timer(_saveAfter, () => unawaited(_save()));
  }

  /// Writes everything if anything changed. Writes run one at a time; a failed write stays dirty and is
  /// retried.
  Future<void> _save() {
    _saveTimer?.cancel();
    _saveTimer = null;
    return _saving = _saving.then((_) => _write());
  }

  Future<void> _write() async {
    if (!_dirty) return;
    _dirty = false;
    try {
      await store.write(settingsFile, _settings.toJson());
      await store.write(whitelistFile, _whitelist.toJson());
      await store.write(stateFile, {'learned': _learnedOnce});
    } catch (_) {
      _dirty = true;
      if (!_disposed) _saveTimer = Timer(_saveRetryAfter, () => unawaited(_save()));
    }
  }
}

/// One notification for a batch of arrivals. Its Whitelist button covers only devices with a fixed address.
Notice noticeFor(List<TrackedDevice> devices) {
  String line(TrackedDevice device) => [
    deviceLabel(name: device.name, manufacturer: device.manufacturer),
    '≈ ${formatDistance(device.distance)}',
    device.address,
    if (!device.kind.isStable) 'rotating address',
  ].join(' · ');
  final listable = devices.where((device) => device.kind.isStable).length;
  final actions = switch (listable) {
    0 => const <String, String>{},
    _ when listable < devices.length => {'whitelist': 'Whitelist $listable'},
    _ => {'whitelist': devices.length == 1 ? 'Whitelist' : 'Whitelist all'},
  };
  return Notice(
    summary: devices.length == 1 ? 'New device nearby' : '${devices.length} new devices nearby',
    body: devices.map(line).join('\n'),
    actions: actions,
  );
}
