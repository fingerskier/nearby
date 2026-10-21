// Scans with BlueZ from the terminal and prints what the app would see, for checking a real adapter.
//
//   dart run tool/scan.dart [seconds] [--classic]
import 'dart:async';
import 'dart:io';

import 'package:nearby/src/core/format.dart';
import 'package:nearby/src/core/settings.dart';
import 'package:nearby/src/core/tracker.dart';
import 'package:nearby/src/scan/bluez_scanner.dart';

Future<void> main(List<String> args) async {
  final seconds = args.map(int.tryParse).whereType<int>().firstOrNull ?? 15;
  final classic = args.contains('--classic');
  final scanner = BluezScanner();
  final tracker = Tracker(const Settings());
  var sightings = 0;
  scanner.states.listen(
    (state) => stdout.writeln('state: ${state.status.name} ${state.adapter ?? ''} ${state.error ?? ''}'),
  );
  scanner.sightings.listen((sighting) {
    sightings += 1;
    tracker.ingest(sighting);
  });
  await scanner.open();
  await scanner.startDiscovery(classic: classic);
  await Future<void>.delayed(Duration(seconds: seconds));
  await scanner.stopDiscovery();
  final devices = tracker.devices();
  stdout.writeln('$sightings sightings from ${devices.length} devices in $seconds s');
  for (final device in devices) {
    final label = deviceLabel(name: device.name, manufacturer: device.manufacturer);
    stdout.writeln(
      [
        device.address,
        kindLabel(device.kind).padRight(9),
        '${device.count}'.padLeft(4),
        '${device.rssi} dBm'.padLeft(8),
        formatDistance(device.distance).padLeft(7),
        if (device.txPower != null) 'tx ${device.txPower}',
        label,
      ].join('  '),
    );
  }
  await scanner.close();
}
