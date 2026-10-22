import 'package:flutter/services.dart';

import 'controller.dart';
import 'scan/scanner.dart';

/// The app's own Android plugin, android/app/src/main/kotlin/io/github/fingerskier/nearby/NearbyPlugin.kt.
class AndroidChannel {
  AndroidChannel({
    this._methods = const MethodChannel('io.github.fingerskier.nearby/methods'),
    this._events = const EventChannel('io.github.fingerskier.nearby/events'),
  });

  final MethodChannel _methods;
  final EventChannel _events;

  /// Everything the plugin reports. An event channel serves a single listener, so this one stream is shared.
  late final Stream<Map<Object?, Object?>> events = _events
      .receiveBroadcastStream()
      .map((event) => event as Map<Object?, Object?>)
      .asBroadcastStream();

  Stream<Map<Object?, Object?>> eventsOf(String type) => events.where((event) => event['type'] == type);

  Future<T?> invoke<T>(String method, [Map<String, Object?>? arguments]) => _methods.invokeMethod<T>(method, arguments);

  /// The Stop button on the "watching" notification.
  Stream<void> get quitRequests => eventsOf('quit');

  /// Keeps the "watching" notification's text current.
  Future<void> setWatching(String text) => invoke<void>('setWatching', {'text': text});

  /// Stops the watching service and ends the process; shut the controller down first.
  Future<void> exit() => invoke<void>('exit');
}

/// What the ongoing "watching" notification says.
String watchingText(NearbyController controller) => switch (controller.scannerState.status) {
  ScannerStatus.noPermission => 'Needs the Nearby devices permission to scan',
  ScannerStatus.poweredOff => 'Bluetooth is off',
  ScannerStatus.noAdapter => 'This phone has no Bluetooth LE',
  ScannerStatus.failed => 'Scanning failed; retrying',
  _ when !controller.ready || controller.scannerState.status == ScannerStatus.starting => 'Starting…',
  _ when controller.paused => 'Paused',
  _ when controller.learning => 'Learning the devices around you',
  _ => 'Watching for new devices',
};
