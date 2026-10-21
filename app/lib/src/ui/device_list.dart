import 'package:flutter/material.dart';

import '../controller.dart';
import '../core/format.dart';
import '../core/tracker.dart';

enum _Filter { unlisted, whitelisted, all }

class DeviceList extends StatefulWidget {
  const DeviceList({super.key, required this.controller, this.shrinkWrap = false});

  final NearbyController controller;

  /// Size to the rows instead of scrolling, for use inside another scroll view.
  final bool shrinkWrap;

  @override
  State<DeviceList> createState() => _DeviceListState();
}

class _DeviceListState extends State<DeviceList> {
  var _filter = _Filter.unlisted;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final whitelist = controller.whitelist;
    final devices = controller.devices;
    final unlisted = devices.where((device) => !whitelist.contains(device.address)).toList();
    final listed = devices.where((device) => whitelist.contains(device.address)).toList();
    final shown = switch (_filter) {
      _Filter.unlisted => unlisted,
      _Filter.whitelisted => listed,
      _Filter.all => devices,
    };
    final canListAll = unlisted.any((device) => device.kind.isStable);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('In range', style: Theme.of(context).textTheme.titleMedium),
            SegmentedButton<_Filter>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: _Filter.unlisted, label: Text('Unlisted ${unlisted.length}')),
                ButtonSegment(value: _Filter.whitelisted, label: Text('Whitelisted ${listed.length}')),
                ButtonSegment(value: _Filter.all, label: Text('All ${devices.length}')),
              ],
              selected: {_filter},
              onSelectionChanged: (selection) => setState(() => _filter = selection.single),
            ),
            if (!controller.learning)
              TextButton.icon(
                onPressed: controller.startLearning,
                icon: const Icon(Icons.school_outlined),
                label: Text('Learn for ${controller.settings.learnMinutes} min'),
              ),
            TextButton.icon(
              onPressed: canListAll ? controller.whitelistAllInRange : null,
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('Whitelist all in range'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              switch (_filter) {
                _Filter.unlisted => devices.isEmpty ? 'Nothing heard yet.' : 'Every device in range is whitelisted.',
                _Filter.whitelisted => 'No whitelisted devices in range.',
                _Filter.all => 'Nothing heard yet.',
              },
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          )
        else if (widget.shrinkWrap)
          for (final device in shown) _DeviceRow(controller: controller, device: device)
        else
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (context, index) => _DeviceRow(controller: controller, device: shown[index]),
            ),
          ),
      ],
    );
  }
}

enum _Action { calibrate, clearCalibration }

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.controller, required this.device});

  final NearbyController controller;
  final TrackedDevice device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final entry = controller.whitelist[device.address];
    final listed = entry != null;
    final label = deviceLabel(label: entry?.label, name: device.name, manufacturer: device.manufacturer);
    final details = [
      device.address,
      kindLabel(device.kind),
      if (device.paired) 'paired',
      if (device.calibrated) 'calibrated',
    ].join(' · ');
    final muted = TextStyle(color: colors.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Tooltip(
            message: device.kind.isStable
                ? (listed ? 'Whitelisted: no alert when it comes and goes' : 'Add to whitelist')
                : 'This address rotates, so it can’t be whitelisted',
            child: Checkbox(
              value: listed,
              onChanged: device.kind.isStable || listed
                  ? (value) => controller.setWhitelisted(device.address, value ?? false)
                  : null,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (!listed && device.kind.isStable) ...[
                      Icon(Icons.circle, size: 8, color: colors.error),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: listed ? FontWeight.normal : FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                Text(details, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.merge(muted)),
              ],
            ),
          ),
          SizedBox(width: 72, child: Text('≈ ${formatDistance(device.distance)}', textAlign: TextAlign.end)),
          SizedBox(
            width: 72,
            child: Text('${device.rssi} dBm', textAlign: TextAlign.end, style: muted),
          ),
          SizedBox(
            width: 52,
            child: Text(formatAge(controller.now.difference(device.lastSeen)), textAlign: TextAlign.end, style: muted),
          ),
          PopupMenuButton<_Action>(
            tooltip: 'More',
            onSelected: (action) => switch (action) {
              _Action.calibrate => controller.calibrate(device.address),
              _Action.clearCalibration => controller.clearCalibration(device.address),
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: _Action.calibrate, child: Text('Calibrate: it is 1 m away now')),
              if (device.calibrated)
                const PopupMenuItem(value: _Action.clearCalibration, child: Text('Clear calibration')),
            ],
          ),
        ],
      ),
    );
  }
}
