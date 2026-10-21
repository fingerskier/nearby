// Throwaway: compares RSSI update counts with and without an RSSI discovery filter. Not committed.
import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

Future<Map<String, int>> run(DBusClient bus, Map<String, DBusValue> filter, int seconds) async {
  final manager = DBusRemoteObjectManager(bus, name: 'org.bluez', path: DBusObjectPath('/'));
  final adapter = DBusRemoteObject(bus, name: 'org.bluez', path: DBusObjectPath('/org/bluez/hci0'));
  final counts = <String, int>{};
  final sub = manager.signals.listen((signal) {
    if (signal is DBusPropertiesChangedSignal &&
        signal.propertiesInterface == 'org.bluez.Device1' &&
        signal.changedProperties.containsKey('RSSI')) {
      counts.update(signal.path.value.split('/').last, (n) => n + 1, ifAbsent: () => 1);
    }
  });
  await adapter.callMethod('org.bluez.Adapter1', 'SetDiscoveryFilter', [
    DBusDict.stringVariant(filter),
  ], replySignature: DBusSignature.empty);
  await adapter.callMethod('org.bluez.Adapter1', 'StartDiscovery', const [], replySignature: DBusSignature.empty);
  await Future<void>.delayed(Duration(seconds: seconds));
  await adapter.callMethod('org.bluez.Adapter1', 'StopDiscovery', const [], replySignature: DBusSignature.empty);
  await sub.cancel();
  return counts;
}

Future<void> main() async {
  final bus = DBusClient.system();
  final a = await run(bus, {'Transport': const DBusString('le'), 'DuplicateData': const DBusBoolean(true)}, 12);
  await Future<void>.delayed(const Duration(seconds: 2));
  final b = await run(bus, {
    'Transport': const DBusString('le'),
    'DuplicateData': const DBusBoolean(true),
    'RSSI': const DBusInt16(-127),
  }, 12);
  int total(Map<String, int> m) => m.values.fold(0, (s, n) => s + n);
  stdout.writeln('without RSSI filter: ${total(a)} updates from ${a.length} devices');
  stdout.writeln('with RSSI -127:      ${total(b)} updates from ${b.length} devices');
  final common = a.keys.toSet().intersection(b.keys.toSet()).toList()..sort();
  for (final key in common) {
    stdout.writeln('${key.substring(0, 9)}…  ${a[key]!.toString().padLeft(4)}  ${b[key]!.toString().padLeft(4)}');
  }
  await bus.close();
}
