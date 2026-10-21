import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nearby/src/alert/notifier.dart';
import 'package:nearby/src/alert/pinger.dart';
import 'package:nearby/src/controller.dart';
import 'package:nearby/src/core/address.dart';
import 'package:nearby/src/scan/bluez_scanner.dart';
import 'package:nearby/src/store.dart';

import 'fakes.dart';

void main() {
  group('sightingFromProperties', () {
    Map<String, DBusValue> device({DBusValue? rssi, DBusValue? txPower, String type = 'random'}) => {
      'Address': const DBusString('c1:75:00:00:00:01'),
      'AddressType': DBusString(type),
      'Name': const DBusString('Govee_H805A_4634'),
      'Icon': const DBusString('thermometer'),
      'Paired': const DBusBoolean(false),
      'ManufacturerData': DBusDict(DBusSignature('q'), DBusSignature('v'), {
        const DBusUint16(0x004C): DBusVariant(DBusArray.byte([1, 2])),
      }),
      'RSSI': ?rssi,
      'TxPower': ?txPower,
    };

    test('reads a BlueZ Device1 property set', () {
      final sighting = sightingFromProperties(device(rssi: const DBusInt16(-71), txPower: const DBusInt16(0)), t0)!;
      expect(sighting.address, 'C1:75:00:00:00:01');
      expect(sighting.kind, AddressKind.staticRandom);
      expect(sighting.rssi, -71);
      expect(sighting.txPower, 0, reason: '0 dBm is a real TX power, not a missing one');
      expect(sighting.name, 'Govee_H805A_4634');
      expect(sighting.icon, 'thermometer');
      expect(sighting.manufacturer, 0x004C);
      expect(sighting.at, t0);
    });

    test('needs an RSSI, and treats 127 as unavailable', () {
      expect(sightingFromProperties(device(), t0), isNull, reason: 'cached device, not heard now');
      expect(sightingFromProperties(device(rssi: const DBusInt16(0)), t0), isNull);
      expect(sightingFromProperties(device(rssi: const DBusInt16(127)), t0), isNull);
      final sighting = sightingFromProperties(device(rssi: const DBusInt16(-50), txPower: const DBusInt16(127)), t0)!;
      expect(sighting.txPower, isNull);
    });
  });

  group('SoundPinger', () {
    test('falls through missing or failing players and remembers the one that worked', () async {
      final tried = <String>[];
      Future<ProcessResult> run(String executable, List<String> arguments) async {
        tried.add(executable);
        return switch (executable) {
          'pw-play' => throw const ProcessException('pw-play', [], 'not found'),
          'paplay' => ProcessResult(0, 1, '', 'no server'),
          _ => ProcessResult(0, 0, '', ''),
        };
      }

      final pinger = SoundPinger(run: run);
      expect(await pinger.ping(), isTrue);
      expect(tried, ['pw-play', 'paplay', 'canberra-gtk-play']);
      tried.clear();
      expect(await pinger.ping(), isTrue);
      expect(tried, ['canberra-gtk-play']);
    });

    test('reports failure when nothing can play', () async {
      final pinger = SoundPinger(run: (_, _) async => ProcessResult(0, 1, '', ''));
      expect(await pinger.ping(), isFalse);
    });
  });

  group('notices', () {
    test('one arrival names the device and offers to whitelist it', () {
      final notice = noticeFor([tracked('AA:00:00:00:00:01', name: 'Lamp', distance: 3.2)]);
      expect(notice.summary, 'New device nearby');
      expect(notice.body, 'Lamp · ≈ 3.2 m · AA:00:00:00:00:01');
      expect(notice.actions, {'whitelist': 'Whitelist'});
    });

    test('several arrivals share one notice', () {
      final notice = noticeFor([tracked('AA:00:00:00:00:01'), tracked('AA:00:00:00:00:02')]);
      expect(notice.summary, '2 new devices nearby');
      expect(notice.body.split('\n'), hasLength(2));
      expect(notice.actions, {'whitelist': 'Whitelist all'});
    });

    test('escapes markup in device names', () {
      expect(escapeMarkup('<b>Tom & Jerry</b>'), '&lt;b&gt;Tom &amp; Jerry&lt;/b&gt;');
    });
  });

  group('JsonFileStore', () {
    late Directory directory;

    setUp(() async => directory = await Directory.systemTemp.createTemp('nearby-store-'));
    tearDown(() => directory.delete(recursive: true));

    test('writes, reads back, and leaves no temporary file', () async {
      final store = JsonFileStore(Directory('${directory.path}/nested'));
      await store.write('a.json', {
        'x': [1, 2],
      });
      expect(await store.read('a.json'), {
        'x': [1, 2],
      });
      expect(Directory('${directory.path}/nested').listSync().map((f) => f.uri.pathSegments.last), ['a.json']);
    });

    test('reads missing or corrupt files as null', () async {
      final store = JsonFileStore(directory);
      expect(await store.read('missing.json'), isNull);
      await File('${directory.path}/bad.json').writeAsString('{not json');
      expect(await store.read('bad.json'), isNull);
    });
  });
}
