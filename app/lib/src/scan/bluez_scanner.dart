import 'dart:async';

import 'package:dbus/dbus.dart';

import '../core/address.dart';
import '../core/sighting.dart';
import 'scanner.dart';

const _bluez = 'org.bluez';
const _adapterInterface = 'org.bluez.Adapter1';
const _deviceInterface = 'org.bluez.Device1';

/// HCI reports 127 when RSSI or TX power isn't available, and BlueZ uses 0 for a missing RSSI.
const _unavailable = 127;

const _retryAfter = Duration(seconds: 5);

/// Reads a sighting from a BlueZ Device1 property set; null without a usable RSSI.
Sighting? sightingFromProperties(Map<String, DBusValue> properties, DateTime at) {
  final rssi = _int(properties['RSSI']);
  final address = _string(properties['Address'])?.toUpperCase();
  if (rssi == null || rssi == 0 || rssi == _unavailable || address == null) return null;
  final txPower = _int(properties['TxPower']);
  final name = _string(properties['Name']);
  return Sighting(
    address: address,
    kind: classifyAddress(address, _string(properties['AddressType'])),
    rssi: rssi,
    at: at,
    name: name == null || name.isEmpty ? null : name,
    txPower: txPower == _unavailable ? null : txPower,
    icon: _string(properties['Icon']),
    manufacturer: _firstCompany(properties['ManufacturerData']),
    paired: _bool(properties['Paired']) ?? false,
  );
}

int? _int(DBusValue? value) => value is DBusInt16 ? value.value : null;

String? _string(DBusValue? value) => value is DBusString ? value.value : null;

bool? _bool(DBusValue? value) => value is DBusBoolean ? value.value : null;

int? _firstCompany(DBusValue? value) {
  if (value is! DBusDict) return null;
  for (final key in value.children.keys) {
    if (key is DBusUint16) return key.value;
  }
  return null;
}

String describeDBusError(Object error) {
  if (error is DBusServiceUnknownException) return 'BlueZ (bluetoothd) is not running.';
  if (error is DBusAccessDeniedException) return 'Not allowed to use Bluetooth: the D-Bus policy denied access.';
  if (error is DBusMethodResponseException) {
    return switch (error.errorName) {
      'org.bluez.Error.NotReady' => 'The Bluetooth adapter is not ready.',
      'org.bluez.Error.Busy' => 'The Bluetooth adapter is busy.',
      _ => '${error.errorName}: ${error.response.values.isEmpty ? '' : error.response.values.first.toNative()}',
    };
  }
  return error.toString();
}

/// Discovers devices through BlueZ on the system D-Bus.
///
/// Discovery runs with DuplicateData and a permissive RSSI filter. Together they make BlueZ update RSSI on
/// every advertisement; without a proximity (RSSI or path-loss) filter, current BlueZ only reports changes
/// of 8 dB or more, so a device sitting still would fall silent. Each RSSI update is one sighting. BlueZ ties
/// the discovery session to this D-Bus connection, so it ends if the app exits without stopping it.
class BluezScanner implements Scanner {
  BluezScanner({DBusClient? bus, DateTime Function()? clock})
    : _bus = bus ?? DBusClient.system(),
      _ownsBus = bus == null,
      _clock = clock ?? DateTime.now;

  final DBusClient _bus;
  final bool _ownsBus;
  final DateTime Function() _clock;
  late final _manager = DBusRemoteObjectManager(_bus, name: _bluez, path: DBusObjectPath('/'));
  final _sightings = StreamController<Sighting>.broadcast();
  final _states = StreamController<ScannerState>.broadcast();
  final _devices = <DBusObjectPath, Map<String, DBusValue>>{};

  /// Every adapter BlueZ has, so another can take over if the one in use goes away.
  final _adapters = <DBusObjectPath, Map<String, DBusValue>>{};
  final _subscriptions = <StreamSubscription<Object?>>[];
  DBusRemoteObject? _adapter;
  var _state = const ScannerState(ScannerStatus.starting);
  var _wanted = false;
  var _classic = false;
  var _discovering = false;
  var _closed = false;
  String? _error;
  Timer? _retry;
  Future<void> _queue = Future.value();

  @override
  Stream<Sighting> get sightings => _sightings.stream;

  @override
  Stream<ScannerState> get states => _states.stream;

  @override
  ScannerState get state => _state;

  Map<String, DBusValue> get _adapterProperties => _adapters[_adapter?.path] ?? const {};

  bool get _powered => _bool(_adapterProperties['Powered']) ?? false;

  @override
  Future<void> open() async {
    // Subscribe first, so nothing that changes during GetManagedObjects is missed.
    _subscriptions
      ..add(_manager.signals.listen(_onSignal))
      ..add(_bus.nameOwnerChanged.where((event) => event.name == _bluez).listen(_onOwnerChanged));
    await _enumerate();
  }

  @override
  Future<void> startDiscovery({required bool classic}) {
    _wanted = true;
    _classic = classic;
    return _reconcile();
  }

  @override
  Future<void> stopDiscovery() {
    _wanted = false;
    return _reconcile();
  }

  /// BlueZ lets any local user scan.
  @override
  Future<void> requestAccess() async {}

  @override
  Future<void> close() async {
    if (_closed) return;
    await stopDiscovery();
    _closed = true;
    _retry?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _sightings.close();
    await _states.close();
    if (_ownsBus) await _bus.close();
  }

  /// Reads every BlueZ object afresh: at open, and when bluetoothd (re)appears.
  Future<void> _enumerate() async {
    try {
      final objects = await _manager.getManagedObjects();
      objects.forEach(_onAdded);
      _error = null;
    } catch (error) {
      _error = describeDBusError(error);
    }
    _refresh();
  }

  /// A bluetoothd that crashes never sends InterfacesRemoved, so forget whatever the old owner had,
  /// and start over with the new one.
  void _onOwnerChanged(DBusNameOwnerChangedEvent event) {
    _adapter = null;
    _adapters.clear();
    _devices.clear();
    _discovering = false;
    _refresh();
    if (event.newOwner != null) unawaited(_enumerate());
  }

  /// Queues a pass that brings BlueZ in line with what was last asked for. Passes run one at a time and
  /// each reads the latest request, so a stop that arrives while a start is in flight still ends discovery.
  Future<void> _reconcile() => _queue = _queue.then((_) => _apply());

  Future<void> _apply() async {
    _retry?.cancel();
    final adapter = _adapter;
    if (_closed || adapter == null || !_powered) {
      _discovering = false;
      return _refresh();
    }
    if (_wanted) {
      try {
        await adapter.callMethod(_adapterInterface, 'SetDiscoveryFilter', [
          DBusDict.stringVariant({
            'Transport': DBusString(_classic ? 'auto' : 'le'),
            'DuplicateData': const DBusBoolean(true),
            'RSSI': const DBusInt16(-127),
          }),
        ], replySignature: DBusSignature.empty);
        await adapter.callMethod(_adapterInterface, 'StartDiscovery', const [], replySignature: DBusSignature.empty);
        _discovering = true;
        _error = null;
      } catch (error) {
        if (error is DBusMethodResponseException && error.errorName == 'org.bluez.Error.InProgress') {
          _discovering = true;
          _error = null;
        } else {
          _discovering = false;
          _error = describeDBusError(error);
          _retry = Timer(_retryAfter, () => unawaited(_reconcile()));
        }
      }
    } else if (_discovering) {
      _discovering = false;
      try {
        await adapter.callMethod(_adapterInterface, 'StopDiscovery', const [], replySignature: DBusSignature.empty);
      } catch (_) {
        // Discovery already ended (adapter reset, powered off, or bluetoothd gone); nothing to stop.
      }
    }
    _refresh();
  }

  void _onSignal(DBusSignal signal) {
    switch (signal) {
      case DBusObjectManagerInterfacesAddedSignal():
        _onAdded(signal.changedPath, signal.interfacesAndProperties);
        _refresh();
      case DBusObjectManagerInterfacesRemovedSignal():
        if (signal.interfaces.contains(_deviceInterface)) _devices.remove(signal.changedPath);
        if (signal.interfaces.contains(_adapterInterface)) {
          _adapters.remove(signal.changedPath);
          // Unplugged: carry on with another adapter if there is one.
          if (signal.changedPath == _adapter?.path) _select();
        }
        _refresh();
      case DBusPropertiesChangedSignal():
        _onPropertiesChanged(signal);
      default:
        break;
    }
  }

  void _onAdded(DBusObjectPath path, Map<String, Map<String, DBusValue>> interfaces) {
    final adapter = interfaces[_adapterInterface];
    if (adapter != null) {
      _adapters[path] = Map.of(adapter);
      if (_adapter == null) _select();
    }
    final device = interfaces[_deviceInterface];
    if (device != null) {
      final properties = _devices[path] = Map.of(device);
      _emit(path, properties);
    }
  }

  void _onPropertiesChanged(DBusPropertiesChangedSignal signal) {
    if (signal.propertiesInterface == _deviceInterface) {
      final properties = _devices[signal.path];
      if (properties == null) return;
      properties.addAll(signal.changedProperties);
      signal.invalidatedProperties.forEach(properties.remove);
      if (signal.changedProperties.containsKey('RSSI')) _emit(signal.path, properties);
    } else if (signal.propertiesInterface == _adapterInterface) {
      final properties = _adapters[signal.path];
      if (properties == null) return;
      final wasPowered = _powered;
      properties.addAll(signal.changedProperties);
      signal.invalidatedProperties.forEach(properties.remove);
      if (signal.path != _adapter?.path) return;
      if (!_powered) {
        _discovering = false;
      } else if (!wasPowered) {
        unawaited(_reconcile());
      }
      _refresh();
    }
  }

  /// Picks the adapter to scan with, preferring one that is powered on, and starts over on it. A new or
  /// restarted bluetoothd brings its adapter back without our discovery session.
  void _select() {
    final paths = _adapters.keys.toList()..sort((a, b) => a.value.compareTo(b.value));
    final path = paths.where((path) => _bool(_adapters[path]!['Powered']) ?? false).firstOrNull ?? paths.firstOrNull;
    _adapter = path == null ? null : DBusRemoteObject(_bus, name: _bluez, path: path);
    _discovering = false;
    if (_wanted && path != null) unawaited(_reconcile());
  }

  void _emit(DBusObjectPath path, Map<String, DBusValue> properties) {
    final adapter = _adapter;
    if (!_wanted || _sightings.isClosed || adapter == null || !path.isInNamespace(adapter.path)) return;
    final sighting = sightingFromProperties(properties, _clock());
    if (sighting != null) _sightings.add(sighting);
  }

  void _refresh() {
    final alias = _string(_adapterProperties['Alias']);
    final next = switch (_adapter) {
      null => ScannerState(ScannerStatus.noAdapter, error: _error),
      _ when !_powered => ScannerState(ScannerStatus.poweredOff, adapter: alias),
      _ when _error != null => ScannerState(ScannerStatus.failed, adapter: alias, error: _error),
      _ when _discovering => ScannerState(ScannerStatus.scanning, adapter: alias),
      _ => ScannerState(ScannerStatus.idle, adapter: alias),
    };
    if (next == _state || _states.isClosed) return;
    _state = next;
    _states.add(next);
  }
}
