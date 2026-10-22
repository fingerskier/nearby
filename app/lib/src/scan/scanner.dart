import '../core/sighting.dart';

enum ScannerStatus {
  starting,
  noAdapter,
  poweredOff,

  /// The user hasn't allowed scanning (Android's Nearby devices permission).
  noPermission,
  idle,
  scanning,
  failed,
}

class ScannerState {
  const ScannerState(this.status, {this.adapter, this.error});

  final ScannerStatus status;

  /// The adapter's alias, once one is found.
  final String? adapter;
  final String? error;

  @override
  bool operator ==(Object other) =>
      other is ScannerState && other.status == status && other.adapter == adapter && other.error == error;

  @override
  int get hashCode => Object.hash(status, adapter, error);
}

/// A source of sightings that can be switched on and off.
abstract interface class Scanner {
  Stream<Sighting> get sightings;

  Stream<ScannerState> get states;

  ScannerState get state;

  Future<void> open();

  /// Starts (or retunes) discovery; keeps retrying while the adapter is missing or off.
  Future<void> startDiscovery({required bool classic});

  Future<void> stopDiscovery();

  /// Asks the user for whatever scanning needs, such as a runtime permission; does nothing where nothing is.
  Future<void> requestAccess();

  Future<void> close();
}
