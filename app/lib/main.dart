import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/alert/android_alerts.dart';
import 'src/alert/notifier.dart';
import 'src/alert/pinger.dart';
import 'src/android_channel.dart';
import 'src/controller.dart';
import 'src/host.dart';
import 'src/scan/android_scanner.dart';
import 'src/scan/bluez_scanner.dart';
import 'src/store.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = JsonFileStore(await getApplicationSupportDirectory());
  final android = Platform.isAndroid;
  final controller = android ? _androidController(store) : _linuxController(store);
  runApp(NearbyApp(controller: controller, host: android ? HostPlatform.android : HostPlatform.linux));
  await controller.start();
}

NearbyController _linuxController(Store store) {
  final controller = NearbyController(
    scanner: BluezScanner(),
    pinger: SoundPinger(),
    notifier: DesktopNotifier(),
    store: store,
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
  return controller;
}

/// On Android the app keeps guarding in the background, behind an ongoing "watching" notification that
/// follows what it is doing and has a Stop button to quit.
NearbyController _androidController(Store store) {
  final channel = AndroidChannel();
  final controller = NearbyController(
    scanner: AndroidScanner(channel),
    pinger: AndroidPinger(channel),
    notifier: AndroidNotifier(channel),
    store: store,
  );
  var shown = '';
  controller.addListener(() {
    final text = watchingText(controller);
    if (text == shown) return;
    shown = text;
    unawaited(channel.setWatching(text));
  });
  channel.quitRequests.listen((_) async {
    await controller.shutdown();
    await channel.exit();
  });
  return controller;
}
