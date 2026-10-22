import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../android_channel.dart';
import '../core/address.dart';
import '../core/sighting.dart';
import 'scanner.dart';

/// Scans with Android's BluetoothLeScanner through the app's plugin (LeScanner.kt), which keeps the scan
/// going across Bluetooth restarts, screen changes and Android's scan limits, and reports its status.
class AndroidScanner implements Scanner {
  AndroidScanner(this._channel, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AndroidChannel _channel;
  final DateTime Function() _clock;
  final _sightings = StreamController<Sighting>.broadcast();
  final _states = StreamController<ScannerState>.broadcast();
  var _state = const ScannerState(ScannerStatus.starting);
  var _wanted = false;
  StreamSubscription<Object?>? _events;
  AppLifecycleListener? _lifecycle;

  @override
  Stream<Sighting> get sightings => _sightings.stream;

  @override
  Stream<ScannerState> get states => _states.stream;

  @override
  ScannerState get state => _state;

  /// Asks for the Nearby devices and notification permissions the first time.
  @override
  Future<void> open() async {
    _events = _channel.events.listen(_onEvent);
    // Coming back from the app's settings page may have granted the permission.
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_channel.invoke<void>('refresh')));
    await _channel.invoke<bool>('requestPermissions');
    _set(scannerStateFromEvent(await _channel.invoke<Map<Object?, Object?>>('state') ?? const {}));
  }

  @override
  Future<void> startDiscovery({required bool classic}) async {
    _wanted = true;
    await _channel.invoke<void>('startScan');
  }

  @override
  Future<void> stopDiscovery() async {
    _wanted = false;
    await _channel.invoke<void>('stopScan');
  }

  /// Shows the permission dialog again, or the app's settings page once Android stops showing it.
  @override
  Future<void> requestAccess() => _channel.invoke<bool>('requestPermissions');

  @override
  Future<void> close() async {
    _wanted = false;
    _lifecycle?.dispose();
    try {
      await _channel.invoke<void>('stopScan');
    } on PlatformException {
      // Nothing left to stop.
    }
    await _events?.cancel();
    await _sightings.close();
    await _states.close();
  }

  void _onEvent(Map<Object?, Object?> event) {
    switch (event['type']) {
      // Results already queued when discovery stopped still arrive; they don't count.
      case 'sighting' when _wanted:
        if (sightingFromEvent(event, _clock()) case final sighting?) _sightings.add(sighting);
      case 'scanState':
        _set(scannerStateFromEvent(event));
    }
  }

  void _set(ScannerState next) {
    if (next == _state) return;
    _state = next;
    _states.add(next);
  }
}

/// A `scanState` event, or the answer to `state`, from LeScanner.kt.
ScannerState scannerStateFromEvent(Map<Object?, Object?> event) {
  final error = event['error'];
  return ScannerState(
    ScannerStatus.values.asNameMap()[event['status']] ?? ScannerStatus.failed,
    error: error is String ? error : null,
  );
}

/// A `sighting` event from LeScanner.kt; null if it is malformed.
Sighting? sightingFromEvent(Map<Object?, Object?> event, DateTime at) {
  final address = event['address'];
  final rssi = event['rssi'];
  if (address is! String || rssi is! int) return null;
  final type = event['addressType'];
  final name = event['name'];
  final txPower = event['txPower'];
  final manufacturer = event['manufacturer'];
  return Sighting(
    address: address.toUpperCase(),
    kind: type is String ? classifyAddress(address, type) : guessAddressKind(address),
    rssi: rssi,
    at: at,
    name: name is String && name.isNotEmpty ? name : null,
    txPower: txPower is int ? txPower : null,
    manufacturer: manufacturer is int ? manufacturer : null,
  );
}
