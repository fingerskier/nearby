import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nearby/src/alert/android_alerts.dart';
import 'package:nearby/src/alert/notifier.dart';
import 'package:nearby/src/android_channel.dart';
import 'package:nearby/src/controller.dart';
import 'package:nearby/src/core/address.dart';
import 'package:nearby/src/core/sighting.dart';
import 'package:nearby/src/scan/android_scanner.dart';
import 'package:nearby/src/scan/scanner.dart';
import 'package:nearby/src/store.dart';

import 'fakes.dart';

const methods = MethodChannel('io.github.fingerskier.nearby/methods');
const events = EventChannel('io.github.fingerskier.nearby/events');
final at = DateTime(2026, 10, 22, 12);

/// Stands in for NearbyPlugin.kt: records method calls and pushes events.
class FakePlugin {
  FakePlugin() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call.method);
      arguments.add(call.arguments);
      return switch (call.method) {
        'state' => {'status': status, 'error': null},
        'requestPermissions' => status != 'noPermission',
        'notify' => notifications ? ++lastId : null,
        'ping' => true,
        _ => null,
      };
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(onListen: (_, sink) => this.sink = sink, onCancel: (_) => sink = null),
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(methods, null);
      messenger.setMockStreamHandler(events, null);
    });
  }

  final calls = <String>[];
  final arguments = <Object?>[];
  var status = 'idle';
  var notifications = true;
  var lastId = 99;
  MockStreamHandlerEventSink? sink;

  Future<void> send(Map<String, Object?> event) async {
    sink!.success(event);
    await pumpEventQueue();
  }
}

Map<String, Object?> sightingEvent(String address, {String? type, int rssi = -60, String? name}) => {
  'type': 'sighting',
  'address': address,
  'addressType': type,
  'rssi': rssi,
  'name': name,
  'txPower': null,
  'manufacturer': 0x004C,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sightingFromEvent', () {
    test('uses the address type when Android reports one', () {
      expect(sightingFromEvent(sightingEvent('c1:75:00:00:00:01', type: 'random'), at)!.kind, AddressKind.staticRandom);
      expect(sightingFromEvent(sightingEvent('6E:1B:00:00:00:01', type: 'public'), at)!.kind, AddressKind.public);
      expect(
        sightingFromEvent(sightingEvent('1D:12:00:00:00:01', type: 'random'), at)!.kind,
        AddressKind.nonResolvable,
      );
    });

    test('guesses from the top bits before Android 15', () {
      expect(sightingFromEvent(sightingEvent('6E:1B:00:00:00:01'), at)!.kind, AddressKind.resolvable);
      expect(sightingFromEvent(sightingEvent('C1:75:00:00:00:01'), at)!.kind, AddressKind.staticRandom);
      expect(sightingFromEvent(sightingEvent('00:1B:63:00:00:01'), at)!.kind, AddressKind.public);
    });

    test('normalises the address and drops empty names', () {
      final sighting = sightingFromEvent(sightingEvent('c1:75:00:00:00:01', name: ''), at)!;
      expect(sighting.address, 'C1:75:00:00:00:01');
      expect(sighting.name, isNull);
      expect(sighting.manufacturer, 0x004C);
      expect(sighting.rssi, -60);
      expect(sighting.at, at);
    });

    test('skips malformed events', () {
      expect(sightingFromEvent({'type': 'sighting', 'rssi': -60}, at), isNull);
      expect(sightingFromEvent({'type': 'sighting', 'address': 'AA:00:00:00:00:01'}, at), isNull);
    });
  });

  test('scannerStateFromEvent reads status names, treating unknown ones as failures', () {
    expect(scannerStateFromEvent({'status': 'noPermission'}), const ScannerState(ScannerStatus.noPermission));
    expect(
      scannerStateFromEvent({'status': 'failed', 'error': 'internal Bluetooth error'}),
      const ScannerState(ScannerStatus.failed, error: 'internal Bluetooth error'),
    );
    expect(scannerStateFromEvent({'status': 'exploded'}).status, ScannerStatus.failed);
  });

  group('AndroidScanner', () {
    late FakePlugin plugin;
    late AndroidScanner scanner;
    late List<Sighting> heard;
    late List<ScannerState> states;

    setUp(() {
      plugin = FakePlugin();
      scanner = AndroidScanner(AndroidChannel(), clock: () => at);
      // Before the plugin's own teardown, which runs last.
      addTearDown(scanner.close);
      heard = [];
      states = [];
      scanner.sightings.listen(heard.add);
      scanner.states.listen(states.add);
    });

    test('asks for permissions on open, then reports the plugin\'s state', () async {
      plugin.status = 'noPermission';
      await scanner.open();
      expect(plugin.calls, ['requestPermissions', 'state']);
      expect(scanner.state.status, ScannerStatus.noPermission);

      await scanner.requestAccess();
      expect(plugin.calls.last, 'requestPermissions');
    });

    test('follows status events', () async {
      await scanner.open();
      await plugin.send({'type': 'scanState', 'status': 'scanning', 'error': null});
      await plugin.send({'type': 'scanState', 'status': 'poweredOff', 'error': null});
      expect(states.map((state) => state.status), [
        ScannerStatus.idle,
        ScannerStatus.scanning,
        ScannerStatus.poweredOff,
      ]);
    });

    test('reports sightings only while discovery is wanted', () async {
      await scanner.open();
      await plugin.send(sightingEvent('AA:00:00:00:00:01'));
      expect(heard, isEmpty);

      await scanner.startDiscovery(classic: false);
      await plugin.send(sightingEvent('AA:00:00:00:00:01'));
      expect(heard.single.address, 'AA:00:00:00:00:01');

      await scanner.stopDiscovery();
      await plugin.send(sightingEvent('AA:00:00:00:00:01'));
      expect(heard, hasLength(1));
      expect(plugin.calls, containsAllInOrder(['startScan', 'stopScan']));
    });

    test('rechecks the permission when the app comes back to the front', () async {
      await scanner.open();
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(plugin.calls.last, 'refresh');
    });
  });

  group('AndroidNotifier', () {
    late FakePlugin plugin;
    late AndroidChannel channel;

    setUp(() {
      plugin = FakePlugin();
      channel = AndroidChannel();
    });

    test('posts the notice and returns its id', () async {
      final id = await AndroidNotifier(channel)
          .show(const Notice(summary: 'New device nearby', body: 'Lamp', actions: {'whitelist': 'Whitelist'}));
      expect(id, 100);
      expect(plugin.arguments.single, {
        'title': 'New device nearby',
        'body': 'Lamp',
        'actions': {'whitelist': 'Whitelist'},
      });
    });

    test('returns null when notifications are turned off', () async {
      plugin.notifications = false;
      expect(await AndroidNotifier(channel).show(const Notice(summary: 's', body: 'b')), isNull);
    });

    test('turns button presses and dismissals into actions and closures', () async {
      final notifier = AndroidNotifier(channel);
      final actions = <NoticeAction>[];
      final closed = <int>[];
      final subscriptions = [notifier.actions.listen(actions.add), notifier.closed.listen(closed.add)];
      await pumpEventQueue();
      await plugin.send({'type': 'action', 'id': 100, 'key': 'whitelist'});
      await plugin.send({'type': 'dismissed', 'id': 101});
      expect(actions.single.id, 100);
      expect(actions.single.key, 'whitelist');
      expect(closed, [101]);
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    });

    test('the pinger plays through the plugin', () async {
      expect(await AndroidPinger(channel).ping(), isTrue);
      expect(plugin.calls, ['ping']);
    });
  });

  group('watchingText', () {
    late FakeScanner scanner;
    late NearbyController controller;

    setUp(() async {
      scanner = FakeScanner();
      controller = NearbyController(
        scanner: scanner,
        pinger: FakePinger(),
        notifier: FakeNotifier(),
        store: MemoryStore({
          whitelistFile: <Object?>[],
          stateFile: {'learned': true},
        }),
      );
    });

    tearDown(() => controller.dispose());

    test('says what the guard is doing', () async {
      expect(watchingText(controller), 'Starting…');
      await controller.start();
      expect(watchingText(controller), 'Watching for new devices');
      controller.startLearning();
      expect(watchingText(controller), 'Learning the devices around you');
      controller.stopLearning();
      controller.pause();
      expect(watchingText(controller), 'Paused');
    });

    test('puts problems first', () async {
      await controller.start();
      controller.pause();
      scanner.deny();
      expect(watchingText(controller), 'Needs the Nearby devices permission to scan');
      scanner.powerOff();
      expect(watchingText(controller), 'Bluetooth is off');
    });
  });
}
