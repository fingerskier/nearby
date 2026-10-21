import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nearby/src/core/address.dart';
import 'package:nearby/src/core/sighting.dart';
import 'package:nearby/src/scan/bluez_scanner.dart';
import 'package:nearby/src/scan/scanner.dart';

const _adapterInterface = 'org.bluez.Adapter1';

/// Just enough of BlueZ's Adapter1 to drive discovery.
class FakeAdapter extends DBusObject {
  FakeAdapter([String name = 'hci0']) : super(DBusObjectPath('/org/bluez/$name'));

  final calls = <String>[];
  Map<String, DBusValue>? filter;
  var powered = true;
  var discovering = false;

  /// While set, StartDiscovery waits for it, like a slow adapter.
  Completer<void>? holdStart;

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
    _adapterInterface: {
      'Address': const DBusString('00:11:22:33:44:55'),
      'Alias': const DBusString('test-adapter'),
      'Powered': DBusBoolean(powered),
    },
  };

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != _adapterInterface) return DBusMethodErrorResponse.unknownInterface();
    calls.add(methodCall.name);
    switch (methodCall.name) {
      case 'SetDiscoveryFilter':
        filter = methodCall.values[0].asStringVariantDict();
        return DBusMethodSuccessResponse();
      case 'StartDiscovery':
        await holdStart?.future;
        discovering = true;
        return DBusMethodSuccessResponse();
      case 'StopDiscovery':
        if (!discovering) return DBusMethodErrorResponse('org.bluez.Error.Failed', [const DBusString('No discovery')]);
        discovering = false;
        return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  Future<void> setPowered(bool value) async {
    powered = value;
    if (!value) discovering = false;
    await emitPropertiesChanged(_adapterInterface, changedProperties: {'Powered': DBusBoolean(value)});
  }
}

class FakeDevice extends DBusObject {
  FakeDevice(this.address, {this.type = 'public', this.name})
    : super(DBusObjectPath('/org/bluez/hci0/dev_${address.replaceAll(':', '_')}'));

  final String address;
  final String type;
  final String? name;

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
    'org.bluez.Device1': {
      'Address': DBusString(address),
      'AddressType': DBusString(type),
      if (name != null) 'Name': DBusString(name!),
    },
  };

  Future<void> advertise(int rssi) =>
      emitPropertiesChanged('org.bluez.Device1', changedProperties: {'RSSI': DBusInt16(rssi)});
}

/// A bluetoothd stand-in: owns org.bluez on the test bus and exports an adapter.
class FakeBluez {
  FakeBluez(DBusAddress address) : client = DBusClient(address);

  final DBusClient client;
  final adapter = FakeAdapter();

  Future<FakeBluez> start() async {
    await client.requestName('org.bluez');
    await client.registerObject(DBusObject(DBusObjectPath('/'), isObjectManager: true));
    await client.registerObject(adapter);
    return this;
  }

  Future<FakeAdapter> addAdapter(String name) async {
    final adapter = FakeAdapter(name);
    await client.registerObject(adapter);
    return adapter;
  }

  /// Unplugs [adapter]: BlueZ reports its interfaces removed.
  Future<void> removeAdapter(FakeAdapter adapter) => client.unregisterObject(adapter);

  Future<FakeDevice> addDevice(FakeDevice device) async {
    await client.registerObject(device);
    return device;
  }

  /// Drops off the bus without unregistering anything, like a crash.
  Future<void> crash() => client.close();
}

Future<void> eventually(bool Function() condition, {String? reason}) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('timed out waiting${reason == null ? '' : ' for $reason'}');
}

/// A private dbus-daemon: unlike the dbus package's in-process server, it routes signals from a well-known
/// name's new owner after the old one drops off, which the restart test depends on.
final _haveDaemon = Process.runSync('sh', ['-c', 'command -v dbus-daemon']).exitCode == 0;

void main() {
  late Process daemon;
  late DBusAddress address;
  late DBusClient bus;
  late FakeBluez bluez;
  late BluezScanner scanner;
  late List<Sighting> sightings;

  setUp(() async {
    daemon = await Process.start('dbus-daemon', ['--session', '--nofork', '--print-address=1']);
    address = DBusAddress((await daemon.stdout.transform(utf8.decoder).transform(const LineSplitter()).first).trim());
    bluez = await FakeBluez(address).start();
    bus = DBusClient(address);
    scanner = BluezScanner(bus: bus);
    sightings = [];
    scanner.sightings.listen(sightings.add);
    await scanner.open();
  });

  tearDown(() async {
    await scanner.close();
    await bus.close();
    await bluez.client.close();
    daemon.kill();
  });

  test(skip: !_haveDaemon, 'starts discovery with a filter that reports every advertisement', () async {
    expect(scanner.state, const ScannerState(ScannerStatus.idle, adapter: 'test-adapter'));
    await scanner.startDiscovery(classic: false);
    expect(bluez.adapter.calls, ['SetDiscoveryFilter', 'StartDiscovery']);
    expect(bluez.adapter.filter, {
      'Transport': const DBusString('le'),
      'DuplicateData': const DBusBoolean(true),
      // Without a proximity filter BlueZ only reports RSSI changes of 8 dB or more.
      'RSSI': const DBusInt16(-127),
    });
    expect(scanner.state.status, ScannerStatus.scanning);
  });

  test(skip: !_haveDaemon, 'reports advertisements only while discovery is wanted', () async {
    final lamp = await bluez.addDevice(FakeDevice('c1:75:00:00:00:01', type: 'random', name: 'Lamp'));
    await scanner.startDiscovery(classic: false);
    await lamp.advertise(-61);
    await lamp.advertise(-61);
    await eventually(() => sightings.length == 2, reason: 'two sightings');
    expect(sightings.first.address, 'C1:75:00:00:00:01');
    expect(sightings.first.kind, AddressKind.staticRandom);
    expect(sightings.first.name, 'Lamp');

    await scanner.stopDiscovery();
    await lamp.advertise(-50);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(sightings, hasLength(2));
    expect(bluez.adapter.calls.last, 'StopDiscovery');
  });

  test(skip: !_haveDaemon, 'a stop that arrives during a slow start still ends discovery', () async {
    bluez.adapter.holdStart = Completer();
    final starting = scanner.startDiscovery(classic: false);
    await eventually(() => bluez.adapter.calls.contains('StartDiscovery'), reason: 'StartDiscovery');
    final stopping = scanner.stopDiscovery();
    bluez.adapter.holdStart!.complete();
    await Future.wait([starting, stopping]);
    expect(bluez.adapter.calls, ['SetDiscoveryFilter', 'StartDiscovery', 'StopDiscovery']);
    expect(bluez.adapter.discovering, isFalse);
    expect(scanner.state.status, ScannerStatus.idle);
  });

  test(skip: !_haveDaemon, 'resumes when Bluetooth is turned back on', () async {
    await scanner.startDiscovery(classic: true);
    expect(bluez.adapter.filter!['Transport'], const DBusString('auto'));
    await bluez.adapter.setPowered(false);
    await eventually(() => scanner.state.status == ScannerStatus.poweredOff, reason: 'powered off');
    await bluez.adapter.setPowered(true);
    await eventually(() => scanner.state.status == ScannerStatus.scanning, reason: 'scanning again');
    expect(bluez.adapter.calls.where((call) => call == 'StartDiscovery'), hasLength(2));
  });

  test(skip: !_haveDaemon, 'moves to another adapter when the one in use is unplugged', () async {
    final spare = await bluez.addAdapter('hci1');
    await scanner.startDiscovery(classic: false);
    expect(bluez.adapter.discovering, isTrue);
    expect(spare.discovering, isFalse);
    await bluez.removeAdapter(bluez.adapter);
    await eventually(() => spare.discovering, reason: 'discovery on hci1');
    expect(scanner.state.status, ScannerStatus.scanning);
  });

  test(skip: !_haveDaemon, 'recovers when bluetoothd restarts without saying goodbye', () async {
    await scanner.startDiscovery(classic: false);
    await bluez.crash();
    await eventually(() => scanner.state.status == ScannerStatus.noAdapter, reason: 'adapter gone');

    bluez = await FakeBluez(address).start();
    await eventually(() => bluez.adapter.discovering, reason: 'discovery on the new daemon');
    expect(scanner.state.status, ScannerStatus.scanning);
    final lamp = await bluez.addDevice(FakeDevice('AA:00:00:00:00:01'));
    await lamp.advertise(-70);
    await eventually(() => sightings.isNotEmpty, reason: 'a sighting from the new daemon');
  });
}
