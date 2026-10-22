import 'package:flutter/material.dart';

import '../controller.dart';
import '../core/format.dart';
import '../host.dart';
import '../scan/scanner.dart';
import 'arrivals.dart';
import 'device_list.dart';
import 'radar.dart';
import 'settings_page.dart';
import 'whitelist_page.dart';

/// Below this width the panels stack and the whole page scrolls.
const _wideLayout = 900.0;

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller, this.host = HostPlatform.linux});

  final NearbyController controller;
  final HostPlatform host;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('nearby'),
          actions: [
            _StatusChip(controller: controller),
            const SizedBox(width: 8),
            IconButton(
              tooltip: controller.paused ? 'Resume scanning' : 'Pause scanning',
              icon: Icon(controller.paused ? Icons.play_arrow : Icons.pause),
              onPressed: controller.ready ? (controller.paused ? controller.resume : controller.pause) : null,
            ),
            IconButton(
              tooltip: 'Whitelist',
              icon: const Icon(Icons.checklist),
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => WhitelistPage(controller: controller))),
            ),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.tune),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsPage(controller: controller, host: host),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        // Android draws behind the navigation bar.
        body: SafeArea(
          top: false,
          child: !controller.ready
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    if (controller.learning) _LearningBanner(controller: controller),
                    if (controller.notificationsBlocked && controller.settings.notify)
                      _ProblemBanner(
                        icon: Icons.notifications_off_outlined,
                        message: controller.settings.ping
                            ? 'Notifications are off for nearby, so new devices only ping.'
                            : 'Notifications are off for nearby, so new devices go unannounced.',
                        action: TextButton(onPressed: controller.requestNotifications, child: const Text('Allow')),
                      ),
                    if (_problem(controller.scannerState, host) case final problem?)
                      _ProblemBanner(
                        message: controller.learningPending
                            ? '$problem Learning the devices around you starts once scanning does.'
                            : problem,
                        action: controller.scannerState.status == ScannerStatus.noPermission
                            ? TextButton(onPressed: controller.requestScannerAccess, child: const Text('Allow'))
                            : null,
                      ),
                    Expanded(child: _Panels(controller: controller)),
                  ],
                ),
        ),
      ),
    );
  }
}

String? _problem(ScannerState state, HostPlatform host) => switch (state.status) {
  ScannerStatus.noAdapter => state.error ?? 'No Bluetooth adapter found.',
  ScannerStatus.poweredOff => switch (host) {
    HostPlatform.linux =>
      'Bluetooth is off. Turn it on (for example `bluetoothctl power on`) and scanning resumes by itself.',
    HostPlatform.android => 'Bluetooth is off. Turn it on and scanning resumes by itself.',
  },
  ScannerStatus.noPermission => 'nearby needs the Nearby devices permission to scan.',
  ScannerStatus.failed => 'Scanning failed: ${state.error}. Retrying…',
  _ => null,
};

class _Panels extends StatelessWidget {
  const _Panels({required this.controller});

  final NearbyController controller;

  @override
  Widget build(BuildContext context) {
    final radar = _Panel(
      child: Radar(devices: controller.devices, whitelist: controller.whitelist),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideLayout) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 4, child: radar),
                const SizedBox(width: 12),
                Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _Panel(child: DeviceList(controller: controller)),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        flex: 2,
                        child: _Panel(child: ArrivalList(controller: controller)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            SizedBox(height: 320, child: radar),
            const SizedBox(height: 12),
            _Panel(child: DeviceList(controller: controller, shrinkWrap: true)),
            const SizedBox(height: 12),
            _Panel(child: ArrivalList(controller: controller, shrinkWrap: true)),
          ],
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.controller});

  final NearbyController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = controller.scannerState.status;
    final (label, background, foreground) = switch (status) {
      ScannerStatus.noAdapter || ScannerStatus.poweredOff || ScannerStatus.noPermission || ScannerStatus.failed => (
        switch (status) {
          ScannerStatus.noAdapter => 'No adapter',
          ScannerStatus.poweredOff => 'Bluetooth off',
          ScannerStatus.noPermission => 'Not allowed',
          _ => 'Scan failed',
        },
        colors.errorContainer,
        colors.onErrorContainer,
      ),
      _ when !controller.ready || status == ScannerStatus.starting => (
        'Starting…',
        colors.surfaceContainerHighest,
        colors.onSurface,
      ),
      _ when controller.paused => ('Paused', colors.surfaceContainerHighest, colors.onSurface),
      _ when controller.learning => (
        'Learning ${formatCountdown(controller.learnLeft)}',
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
      ),
      _ when controller.resting => ('Guarding · resting', colors.primaryContainer, colors.onPrimaryContainer),
      _ => ('Guarding', colors.primaryContainer, colors.onPrimaryContainer),
    };
    return Semantics(
      liveRegion: true,
      child: Chip(
        label: Text(label),
        backgroundColor: background,
        labelStyle: TextStyle(color: foreground),
        side: BorderSide.none,
      ),
    );
  }
}

class _LearningBanner extends StatelessWidget {
  const _LearningBanner({required this.controller});

  final NearbyController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      leading: const Icon(Icons.school_outlined),
      content: Text(
        'Learning: every device with a stable address seen in the next '
        '${formatCountdown(controller.learnLeft)} is added to the whitelist. '
        'Unlisted devices that arrive after that trigger an alert.',
      ),
      actions: [TextButton(onPressed: controller.stopLearning, child: const Text('Stop learning'))],
    );
  }
}

class _ProblemBanner extends StatelessWidget {
  const _ProblemBanner({required this.message, this.action, this.icon = Icons.bluetooth_disabled});

  final String message;
  final Widget? action;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MaterialBanner(
      backgroundColor: colors.errorContainer,
      leading: Icon(icon, color: colors.onErrorContainer),
      content: Text(message, style: TextStyle(color: colors.onErrorContainer)),
      actions: [action ?? const SizedBox.shrink()],
    );
  }
}
