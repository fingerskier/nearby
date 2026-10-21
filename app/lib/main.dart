import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/alert/notifier.dart';
import 'src/alert/pinger.dart';
import 'src/controller.dart';
import 'src/scan/bluez_scanner.dart';
import 'src/store.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = NearbyController(
    scanner: BluezScanner(),
    pinger: SoundPinger(),
    notifier: DesktopNotifier(),
    store: JsonFileStore(await getApplicationSupportDirectory()),
  );
  // Closing the window, Ctrl-C and logout all write unsaved changes and end the discovery session first.
  AppLifecycleListener(
    onExitRequested: () async {
      await controller.shutdown();
      return AppExitResponse.exit;
    },
  );
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      await controller.shutdown();
      exit(0);
    });
  }
  runApp(NearbyApp(controller: controller));
  await controller.start();
}
