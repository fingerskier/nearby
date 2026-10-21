import 'address.dart';

/// One advertisement (or inquiry result) heard from a device.
class Sighting {
  const Sighting({
    required this.address,
    required this.kind,
    required this.rssi,
    required this.at,
    this.name,
    this.txPower,
    this.icon,
    this.manufacturer,
    this.paired = false,
  });

  /// Upper-case, colon-separated, as BlueZ reports it.
  final String address;
  final AddressKind kind;
  final int rssi;
  final DateTime at;
  final String? name;

  /// Advertised TX power, dBm.
  final int? txPower;

  /// freedesktop icon name BlueZ derives from the device class or appearance, e.g. "phone".
  final String? icon;

  /// Bluetooth SIG company identifier from the manufacturer data, if any.
  final int? manufacturer;
  final bool paired;
}
