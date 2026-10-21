import 'dart:math' as math;

import 'address.dart';
import 'distance.dart';
import 'kalman.dart';
import 'settings.dart';
import 'sighting.dart';

class TrackedDevice {
  const TrackedDevice({
    required this.address,
    required this.kind,
    required this.rssi,
    required this.smoothed,
    required this.ref1m,
    required this.distance,
    required this.calibrated,
    required this.firstSeen,
    required this.lastSeen,
    required this.count,
    required this.angle,
    this.name,
    this.icon,
    this.manufacturer,
    this.txPower,
    this.paired = false,
  });

  final String address;
  final AddressKind kind;
  final String? name;
  final String? icon;
  final int? manufacturer;
  final bool paired;

  /// Latest raw reading, dBm.
  final int rssi;

  /// Filtered RSSI, dBm.
  final double smoothed;
  final int? txPower;

  /// RSSI expected at 1 m for this device.
  final double ref1m;

  /// Estimated distance, metres.
  final double distance;
  final bool calibrated;
  final DateTime firstSeen;
  final DateTime lastSeen;

  /// Sightings received.
  final int count;

  /// Stable pseudo-bearing in radians; one receiver measures range only, never direction.
  final double angle;
}

/// FNV-1a, mapped onto [0, 2π).
double angleFor(String id) {
  var hash = 0x811c9dc5;
  for (final unit in id.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash / 0x100000000 * 2 * math.pi;
}

class _Entry {
  _Entry(Sighting first, this.filter)
    : address = first.address,
      kind = first.kind,
      firstSeen = first.at,
      lastSeen = first.at,
      rssi = first.rssi,
      smoothed = first.rssi.toDouble(),
      angle = angleFor(first.address);

  final String address;
  final Kalman1D filter;
  final DateTime firstSeen;
  final double angle;
  AddressKind kind;
  String? name;
  String? icon;
  int? manufacturer;
  int? txPower;
  bool paired = false;
  DateTime lastSeen;
  int rssi;
  double smoothed;
  double ref1m = 0;
  double distance = 0;
  bool calibrated = false;
  int count = 0;

  TrackedDevice snapshot() => TrackedDevice(
    address: address,
    kind: kind,
    name: name,
    icon: icon,
    manufacturer: manufacturer,
    paired: paired,
    rssi: rssi,
    smoothed: smoothed,
    txPower: txPower,
    ref1m: ref1m,
    distance: distance,
    calibrated: calibrated,
    firstSeen: firstSeen,
    lastSeen: lastSeen,
    count: count,
    angle: angle,
  );
}

/// Turns a stream of sightings into smoothed, ranged devices.
class Tracker {
  Tracker(this._settings);

  Settings _settings;
  final _entries = <String, _Entry>{};

  int get length => _entries.length;

  void configure(Settings settings) {
    _settings = settings;
    for (final entry in _entries.values) {
      entry.filter.r = settings.noiseDb * settings.noiseDb;
      _range(entry);
    }
  }

  /// Folds [sighting] into its device and returns the device as it stands now.
  TrackedDevice ingest(Sighting sighting) {
    final entry = _entries.putIfAbsent(
      sighting.address,
      () => _Entry(sighting, Kalman1D(Settings.processNoise, _settings.noiseDb * _settings.noiseDb)),
    );
    // Names, TX power and manufacturer data often arrive in only some packets (e.g. scan responses),
    // so keep the last known value.
    entry
      ..kind = sighting.kind
      ..name = sighting.name ?? entry.name
      ..icon = sighting.icon ?? entry.icon
      ..manufacturer = sighting.manufacturer ?? entry.manufacturer
      ..txPower = sighting.txPower ?? entry.txPower
      ..paired = sighting.paired
      ..rssi = sighting.rssi
      ..smoothed = entry.filter.update(sighting.rssi.toDouble(), sighting.at)
      ..count += 1;
    if (sighting.at.isAfter(entry.lastSeen)) entry.lastSeen = sighting.at;
    _range(entry);
    return entry.snapshot();
  }

  /// Forgets devices not heard from within [Settings.awayAfter]; returns their addresses.
  List<String> prune(DateTime now) {
    final cutoff = now.subtract(_settings.awayAfter);
    final gone = [
      for (final entry in _entries.values)
        if (entry.lastSeen.isBefore(cutoff)) entry.address,
    ];
    gone.forEach(_entries.remove);
    return gone;
  }

  TrackedDevice? operator [](String address) => _entries[address]?.snapshot();

  /// Snapshots, nearest first.
  List<TrackedDevice> devices() {
    final list = [for (final entry in _entries.values) entry.snapshot()];
    list.sort((a, b) {
      final byDistance = a.distance.compareTo(b.distance);
      return byDistance != 0 ? byDistance : a.address.compareTo(b.address);
    });
    return list;
  }

  void clear() => _entries.clear();

  void _range(_Entry entry) {
    final calibrated = _settings.calibrations[entry.address];
    entry
      ..calibrated = calibrated != null
      ..ref1m = resolveRef1m(
        calibrated: calibrated,
        txPower: entry.txPower,
        useTxPower: _settings.useTxPower,
        fallback: _settings.ref1m,
      )
      ..distance = distanceFromRssi(entry.smoothed, PathLoss(ref1m: entry.ref1m, n: _settings.n));
  }
}
