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
  runApp(NearbyApp(controller: controller));
  await controller.start();
}
