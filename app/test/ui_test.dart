import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nearby/src/controller.dart';
import 'package:nearby/src/core/address.dart';
import 'package:nearby/src/host.dart';
import 'package:nearby/src/store.dart';
import 'package:nearby/src/ui/app.dart';

import 'fakes.dart';

const lamp = 'AA:00:00:00:00:01';
const stranger = 'AA:00:00:00:00:02';
const phone = '6E:1B:00:00:00:04';

/// Learning has finished before and nothing is whitelisted.
const guarding = <String, Object?>{
  whitelistFile: <Object?>[],
  stateFile: {'learned': true},
};

void main() {
  late FakeScanner scanner;
  NearbyController? running;

  /// testWidgets that also stops the controller's timers before the binding checks for leftovers.
  void appTest(String description, Future<void> Function(WidgetTester tester) body) {
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      running?.dispose();
      running = null;
    });
  }

  Future<NearbyController> pumpApp(
    WidgetTester tester, {
    Map<String, Object?>? saved,
    HostPlatform host = HostPlatform.linux,
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    scanner = FakeScanner();
    final controller = NearbyController(
      scanner: scanner,
      pinger: FakePinger(),
      notifier: FakeNotifier(),
      store: MemoryStore(saved),
      clock: () => tester.binding.clock.now(),
    );
    running = controller;
    await tester.pumpWidget(NearbyApp(controller: controller, host: host));
    await controller.start();
    await tester.pump();
    return controller;
  }

  void hear(WidgetTester tester, String address, {String? name, AddressKind kind = AddressKind.public}) {
    for (var i = 0; i < 2; i++) {
      scanner.emit(sight(address, at: tester.binding.clock.now(), name: name, kind: kind));
    }
  }

  appTest('a first run shows the learning banner until stopped', (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('Learning: every device'), findsOneWidget);
    expect(find.textContaining('Learning 2:00'), findsOneWidget);
    await tester.tap(find.text('Stop learning'));
    await tester.pump();
    expect(find.textContaining('Learning: every device'), findsNothing);
    expect(find.text('Guarding'), findsOneWidget);
  });

  appTest('lists unlisted devices, and ticking one whitelists it', (tester) async {
    final controller = await pumpApp(tester, saved: guarding);
    hear(tester, lamp, name: 'Lamp');
    hear(tester, stranger, name: 'Stranger');
    hear(tester, phone, kind: AddressKind.resolvable);
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Unlisted 3'), findsOneWidget);
    expect(find.text('Lamp'), findsWidgets);
    expect(find.text('Arrivals'), findsOneWidget);
    expect(find.text('$stranger · public'), findsOneWidget);
    expect(find.text('$phone · rotating'), findsOneWidget);

    final lampRow = find.ancestor(of: find.text('$lamp · public'), matching: find.byType(Row)).first;
    await tester.tap(find.descendant(of: lampRow, matching: find.byType(Checkbox)));
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.whitelist.contains(lamp), isTrue);
    expect(find.text('Unlisted 2'), findsOneWidget);
    expect(find.text('Whitelisted 1'), findsOneWidget);

    final phoneRow = find.ancestor(of: find.text('$phone · rotating'), matching: find.byType(Row)).first;
    final phoneBox = tester.widget<Checkbox>(find.descendant(of: phoneRow, matching: find.byType(Checkbox)));
    expect(phoneBox.onChanged, isNull, reason: 'a rotating address can’t be whitelisted');
  });

  appTest('arrivals can be whitelisted from the log', (tester) async {
    final controller = await pumpApp(tester, saved: guarding);
    hear(tester, stranger, name: 'Stranger');
    await tester.pump(const Duration(seconds: 2));
    expect(controller.arrivals, hasLength(1));
    await tester.tap(find.widgetWithText(TextButton, 'Whitelist'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.whitelist.contains(stranger), isTrue);
    expect(find.text('whitelisted'), findsOneWidget);
  });

  appTest('shows when Bluetooth is off', (tester) async {
    await pumpApp(tester, saved: guarding);
    scanner.powerOff();
    await tester.pump();
    expect(find.text('Bluetooth off'), findsOneWidget);
    expect(find.textContaining('Bluetooth is off.'), findsOneWidget);
  });

  appTest('on a phone, a missing permission can be asked for again, and Linux-only options are hidden', (tester) async {
    await pumpApp(tester, saved: guarding, host: HostPlatform.android, size: const Size(412, 915));
    scanner.deny();
    await tester.pump();
    expect(find.text('Not allowed'), findsOneWidget);
    expect(find.textContaining('Nearby devices permission'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Allow'));
    expect(scanner.calls.last, 'request access');

    scanner.powerOff();
    await tester.pump();
    expect(find.text('Bluetooth is off. Turn it on and scanning resumes by itself.'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Include Bluetooth Classic'), findsNothing);
    expect(find.text('Show a notification, with a button to whitelist the device'), findsOneWidget);
  });

  appTest('settings and whitelist pages open and edit', (tester) async {
    final controller = await pumpApp(tester, saved: guarding);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Include Bluetooth Classic'), findsOneWidget);
    await tester.tap(find.text('Ping'));
    await tester.pump();
    expect(controller.settings.ping, isFalse);
    await tester.tap(find.text('Only alert on nearby devices'));
    await tester.pump();
    expect(controller.settings.alertRadius, 5);
    await tester.pageBack();
    await tester.pumpAndSettle();

    controller.setWhitelisted(lamp, true);
    await tester.tap(find.byTooltip('Whitelist'));
    await tester.pumpAndSettle();
    expect(find.textContaining('$lamp · not in range'), findsOneWidget);
    await tester.tap(find.byTooltip('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Desk lamp');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.whitelist[lamp]!.label, 'Desk lamp');
    await tester.tap(find.byTooltip('Remove from whitelist'));
    await tester.pumpAndSettle();
    expect(controller.whitelist.length, 0);
  });
}
