import 'package:flutter/material.dart';

import '../controller.dart';
import '../core/settings.dart';
import '../host.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller, this.host = HostPlatform.linux});

  final NearbyController controller;
  final HostPlatform host;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final settings = controller.settings;
        void update(Settings next) => controller.updateSettings(next);
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    const _Heading('Alerts'),
                    SwitchListTile(
                      title: const Text('Ping'),
                      subtitle: const Text('Play a sound when an unlisted device arrives'),
                      value: settings.ping,
                      onChanged: (value) => update(settings.copyWith(ping: value)),
                    ),
                    SwitchListTile(
                      title: const Text('Notification'),
                      subtitle: Text(
                        '${host == HostPlatform.linux ? 'Show a desktop notification' : 'Show a notification'}, '
                        'with a button to whitelist the device',
                      ),
                      value: settings.notify,
                      onChanged: (value) => update(settings.copyWith(notify: value)),
                    ),
                    SwitchListTile(
                      title: const Text('Alert on rotating addresses'),
                      subtitle: const Text(
                        'Phones, watches and earbuds change their address about every 15 minutes, '
                        'so each change looks like a new device and can’t be whitelisted.',
                      ),
                      value: settings.alertRotating,
                      onChanged: (value) => update(settings.copyWith(alertRotating: value)),
                    ),
                    SwitchListTile(
                      title: const Text('Only alert on nearby devices'),
                      subtitle: Text(
                        settings.alertRadius == null
                            ? 'Alerts at any distance'
                            : 'Within about ${_metres(settings.alertRadius!)}',
                      ),
                      value: settings.alertRadius != null,
                      onChanged: (value) => update(settings.copyWith(alertRadius: value ? 5.0 : null)),
                    ),
                    if (settings.alertRadius != null)
                      _SliderTile(
                        label: 'Alert radius',
                        value: settings.alertRadius!,
                        limit: Settings.alertRadiusLimit,
                        format: _metres,
                        onChanged: (value) => update(settings.copyWith(alertRadius: value)),
                      ),
                    _SliderTile(
                      label: 'Quiet after an alert',
                      help: 'The same device won’t alert again for this long, even if it leaves and returns',
                      value: settings.reAlertMinutes.toDouble(),
                      limit: Settings.reAlertLimit,
                      format: _minutes,
                      onChanged: (value) => update(settings.copyWith(reAlertMinutes: value.round())),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.notifications_active_outlined),
                          label: const Text('Test alert'),
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final result = await controller.testAlert();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  [
                                    result.ping ? 'Ping played' : _noPing(host),
                                    result.notify ? 'notification shown' : _noNotification(host),
                                  ].join(' · '),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const _Heading('Scanning'),
                    if (host == HostPlatform.linux)
                      SwitchListTile(
                        title: const Text('Include Bluetooth Classic'),
                        subtitle: const Text(
                          'Also finds older Classic devices, but only ones in discoverable mode, and slows LE updates',
                        ),
                        value: settings.includeClassic,
                        onChanged: (value) => update(settings.copyWith(includeClassic: value)),
                      ),
                    SwitchListTile(
                      title: const Text('Rest between scans'),
                      subtitle: const Text(
                        'Scanning shares the radio with connected devices; resting helps if a headset drops out',
                      ),
                      value: !settings.continuous,
                      onChanged: (value) => update(settings.copyWith(scanOffSeconds: value ? 20 : 0)),
                    ),
                    if (!settings.continuous) ...[
                      _SliderTile(
                        label: 'Scan for',
                        value: settings.scanOnSeconds.toDouble(),
                        limit: Settings.scanOnLimit,
                        format: _seconds,
                        onChanged: (value) => update(settings.copyWith(scanOnSeconds: value.round())),
                      ),
                      _SliderTile(
                        label: 'Then rest for',
                        value: settings.scanOffSeconds.toDouble(),
                        limit: const Limit(5, 600, 5),
                        format: _seconds,
                        onChanged: (value) => update(settings.copyWith(scanOffSeconds: value.round())),
                      ),
                    ],
                    _SliderTile(
                      label: 'Out of range after',
                      help:
                          'A device not heard from for this long has left; seeing it again later counts as an arrival',
                      value: settings.outOfRangeSeconds.toDouble(),
                      limit: Settings.outOfRangeLimit,
                      format: _seconds,
                      onChanged: (value) => update(settings.copyWith(outOfRangeSeconds: value.round())),
                    ),
                    const _Heading('Learning'),
                    _SliderTile(
                      label: 'Learn for',
                      help: 'Learning whitelists every device with a stable address it sees',
                      value: settings.learnMinutes.toDouble(),
                      limit: Settings.learnLimit,
                      format: _minutes,
                      onChanged: (value) => update(settings.copyWith(learnMinutes: value.round())),
                    ),
                    const _Heading('Distance estimate'),
                    _SliderTile(
                      label: 'Path-loss exponent',
                      help: 'About 2 in open space, 2.5–4 indoors and through walls',
                      value: settings.n,
                      limit: Settings.nLimit,
                      format: (value) => value.toStringAsFixed(1),
                      onChanged: (value) => update(settings.copyWith(n: value)),
                    ),
                    _SliderTile(
                      label: 'Signal at 1 m',
                      help: 'Used for devices without a calibration or advertised TX power',
                      value: settings.ref1m,
                      limit: Settings.ref1mLimit,
                      format: (value) => '${value.round()} dBm',
                      onChanged: (value) => update(settings.copyWith(ref1m: value)),
                    ),
                    _SliderTile(
                      label: 'Reading noise',
                      help: 'Higher smooths more but follows movement more slowly',
                      value: settings.noiseDb,
                      limit: Settings.noiseDbLimit,
                      format: (value) => '${value.toStringAsFixed(1)} dB',
                      onChanged: (value) => update(settings.copyWith(noiseDb: value)),
                    ),
                    SwitchListTile(
                      title: const Text('Use advertised TX power'),
                      subtitle: const Text('Derive the 1 m signal from the TX power a device advertises'),
                      value: settings.useTxPower,
                      onChanged: (value) => update(settings.copyWith(useTxPower: value)),
                    ),
                    ListTile(
                      title: Text('${settings.calibrations.length} calibrated devices'),
                      subtitle: const Text('Calibrate a device from its menu while it is 1 m away'),
                      trailing: TextButton(
                        onPressed: settings.calibrations.isEmpty
                            ? null
                            : () => update(settings.copyWith(calibrations: const {})),
                        child: const Text('Clear all'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => update(Settings(calibrations: settings.calibrations)),
                          child: const Text('Reset settings to defaults'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _noPing(HostPlatform host) => switch (host) {
  HostPlatform.linux => 'No sound player worked (pw-play, paplay, canberra-gtk-play)',
  HostPlatform.android => 'No notification sound is set',
};

String _noNotification(HostPlatform host) => switch (host) {
  HostPlatform.linux => 'no notification server answered',
  HostPlatform.android => 'notifications are turned off for nearby',
};

String _metres(double value) => value < 10 ? '${value.toStringAsFixed(1)} m' : '${value.round()} m';

String _seconds(double value) =>
    value < 60 ? '${value.round()} s' : '${value ~/ 60} min${value % 60 == 0 ? '' : ' ${(value % 60).round()} s'}';

String _minutes(double value) =>
    value < 60 ? '${value.round()} min' : '${value ~/ 60} h${value % 60 == 0 ? '' : ' ${(value % 60).round()} min'}';

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.limit,
    required this.format,
    required this.onChanged,
    this.help,
  });

  final String label;
  final String? help;
  final double value;
  final Limit limit;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text('$label: ${format(value)}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (help != null) Text(help!),
          Slider(
            value: value.clamp(limit.min, limit.max),
            min: limit.min,
            max: limit.max,
            divisions: limit.divisions,
            label: format(value),
            semanticFormatterCallback: format,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
