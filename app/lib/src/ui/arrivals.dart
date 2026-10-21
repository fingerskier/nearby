import 'package:flutter/material.dart';

import '../controller.dart';
import '../core/format.dart';

/// Recent alerts: unlisted devices that came into range.
class ArrivalList extends StatelessWidget {
  const ArrivalList({super.key, required this.controller, this.shrinkWrap = false});

  final NearbyController controller;

  /// Size to the rows instead of scrolling, for use inside another scroll view.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final arrivals = controller.arrivals;
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    Widget row(ArrivalRecord arrival) {
      final device = arrival.device;
      final entry = controller.whitelist[device.address];
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 72, child: Text(_clock(arrival.at), style: muted)),
            Expanded(
              child: Text(
                '${deviceLabel(label: entry?.label, name: device.name, manufacturer: device.manufacturer)}'
                '  ·  ≈ ${formatDistance(device.distance)}  ·  ${device.address}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (entry == null && device.kind.isStable)
              TextButton(
                onPressed: () => controller.setWhitelisted(device.address, true),
                child: const Text('Whitelist'),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(entry == null ? 'rotating' : 'whitelisted', style: muted),
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Row(
          children: [
            Text('Arrivals', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 8),
            Text('${arrivals.length}', style: muted),
            const Spacer(),
            TextButton(onPressed: arrivals.isEmpty ? null : controller.clearArrivals, child: const Text('Clear')),
          ],
        ),
        if (arrivals.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('No unlisted arrivals yet.', textAlign: TextAlign.center, style: muted),
          )
        else if (shrinkWrap)
          for (final arrival in arrivals) row(arrival)
        else
          Expanded(
            child: ListView.builder(itemCount: arrivals.length, itemBuilder: (context, index) => row(arrivals[index])),
          ),
      ],
    );
  }
}

String _clock(DateTime at) {
  String two(int value) => value.toString().padLeft(2, '0');
  final local = at.toLocal();
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
