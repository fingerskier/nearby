final _addressPattern = RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$');

/// Upper-cases [address] and returns it if it looks like "AA:BB:CC:DD:EE:FF", otherwise null.
String? normalizeAddress(String address) {
  final upper = address.trim().toUpperCase();
  return _addressPattern.hasMatch(upper) ? upper : null;
}

class WhitelistEntry {
  const WhitelistEntry({required this.address, required this.added, this.label, this.name});

  final String address;
  final DateTime added;

  /// The user's name for the device; null shows whatever name the device advertises.
  final String? label;

  /// The name the device advertised when it was whitelisted, for when it is out of range.
  final String? name;

  WhitelistEntry withLabel(String? label) => WhitelistEntry(
    address: address,
    added: added,
    label: label == null || label.trim().isEmpty ? null : label.trim(),
    name: name,
  );

  Map<String, Object?> toJson() => {
    'address': address,
    'label': label,
    'name': name,
    'added': added.toUtc().toIso8601String(),
  };
}

/// Devices that may come and go without an alert, keyed by address.
class Whitelist {
  Whitelist([Iterable<WhitelistEntry> entries = const []]) {
    for (final entry in entries) {
      _entries[entry.address] = entry;
    }
  }

  final _entries = <String, WhitelistEntry>{};

  int get length => _entries.length;

  bool contains(String address) => _entries.containsKey(address);

  WhitelistEntry? operator [](String address) => _entries[address];

  /// Entries in the order they were added.
  List<WhitelistEntry> get entries => _entries.values.toList();

  /// Returns false if [address] is invalid or already listed.
  bool add(String address, {String? label, String? name, required DateTime at}) {
    final normalized = normalizeAddress(address);
    if (normalized == null || _entries.containsKey(normalized)) return false;
    _entries[normalized] = WhitelistEntry(address: normalized, added: at, name: name).withLabel(label);
    return true;
  }

  bool remove(String address) => _entries.remove(address) != null;

  void rename(String address, String? label) {
    final entry = _entries[address];
    if (entry != null) _entries[address] = entry.withLabel(label);
  }

  List<Object?> toJson() => [for (final entry in _entries.values) entry.toJson()];

  /// Accepts anything (e.g. decoded JSON from disk) and keeps the entries that make sense.
  static Whitelist fromJson(Object? raw) {
    final whitelist = Whitelist();
    if (raw is! List) return whitelist;
    for (final item in raw) {
      if (item is! Map) continue;
      final address = item['address'];
      if (address is! String) continue;
      final added = item['added'] is String ? DateTime.tryParse(item['added'] as String) : null;
      final label = item['label'];
      final name = item['name'];
      whitelist.add(
        address,
        label: label is String ? label : null,
        name: name is String ? name : null,
        at: added ?? DateTime.utc(1970),
      );
    }
    return whitelist;
  }
}
