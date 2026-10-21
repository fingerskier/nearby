import 'address.dart';

String formatDistance(double metres) => metres < 10 ? '${metres.toStringAsFixed(1)} m' : '${metres.round()} m';

String formatAge(Duration age) {
  if (age < const Duration(milliseconds: 1500)) return 'now';
  if (age < const Duration(minutes: 1)) return '${(age.inMilliseconds / 1000).round()} s';
  if (age < const Duration(hours: 1)) return '${age.inMinutes} min';
  return '${age.inHours} h';
}

/// "m:ss", for countdowns.
String formatCountdown(Duration left) {
  final seconds = left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// A few Bluetooth SIG company identifiers that commonly show up in advertisements.
const _companies = {
  0x0002: 'Intel',
  0x0006: 'Microsoft',
  0x000F: 'Broadcom',
  0x004C: 'Apple',
  0x0059: 'Nordic',
  0x0075: 'Samsung',
  0x0087: 'Garmin',
  0x00C4: 'LG',
  0x00E0: 'Google',
  0x012D: 'Sony',
  0x0171: 'Amazon',
  0x0499: 'Ruuvi',
};

String? companyName(int? id) => id == null ? null : _companies[id];

/// What to call a device: the user's label, then its advertised name, then its maker.
String deviceLabel({String? label, String? name, int? manufacturer}) {
  if (label != null) return label;
  if (name != null && name.isNotEmpty) return name;
  final company = companyName(manufacturer);
  return company == null ? 'Unnamed device' : 'Unnamed $company device';
}

String kindLabel(AddressKind kind) => switch (kind) {
  AddressKind.public => 'public',
  AddressKind.staticRandom => 'static',
  AddressKind.resolvable => 'rotating',
  AddressKind.nonResolvable => 'anonymous',
};
