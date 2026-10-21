/// What a Bluetooth address says about the device's identity.
enum AddressKind {
  /// IEEE-assigned and fixed for the life of the device.
  public,

  /// Random, but fixed until the device is reset.
  staticRandom,

  /// Changes every few minutes (typically 15); only hosts paired with the device can resolve it.
  resolvable,

  /// Changes at will and can't be resolved by anyone.
  nonResolvable;

  /// Whether the device keeps this address, so a whitelist entry for it stays valid.
  bool get isStable => this == public || this == staticRandom;
}

/// Classifies a BlueZ address ("AA:BB:CC:DD:EE:FF") given its AddressType ("public" or "random").
/// A random address carries its subtype in its two most significant bits (Core spec Vol 6, Part B, 1.3).
AddressKind classifyAddress(String address, String? addressType) {
  if (addressType != 'random') return AddressKind.public;
  final top = address.length >= 2 ? int.tryParse(address.substring(0, 2), radix: 16) : null;
  return switch (top == null ? null : top >> 6) {
    3 => AddressKind.staticRandom,
    1 => AddressKind.resolvable,
    _ => AddressKind.nonResolvable,
  };
}
