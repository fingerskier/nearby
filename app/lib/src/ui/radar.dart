import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/radar_scale.dart';
import '../core/tracker.dart';
import '../core/whitelist.dart';

/// Devices around the receiver at the centre. Distance from the centre is the range estimate;
/// the angle is a stable hash of the address, since one receiver can't measure direction.
class Radar extends StatefulWidget {
  const Radar({super.key, required this.devices, required this.whitelist});

  final List<TrackedDevice> devices;
  final Whitelist whitelist;

  @override
  State<Radar> createState() => _RadarState();
}

class _RadarState extends State<Radar> {
  var _range = 5.0;

  @override
  Widget build(BuildContext context) {
    final farthest = widget.devices.fold(0.0, (far, device) => math.max(far, device.distance));
    _range = nextRange(_range, farthest);
    final unknown = widget.devices.where((device) => !widget.whitelist.contains(device.address)).length;
    return Semantics(
      label: 'Radar: ${widget.devices.length} devices in range, $unknown not whitelisted',
      child: CustomPaint(
        painter: _RadarPainter(
          devices: widget.devices,
          whitelist: widget.whitelist,
          range: _range,
          colors: Theme.of(context).colorScheme,
          text: Theme.of(context).textTheme.labelSmall!,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// At most this many device names, unlisted and nearest first; a name that would overlap another is skipped.
const _maxLabels = 8;

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.devices,
    required this.whitelist,
    required this.range,
    required this.colors,
    required this.text,
  });

  final List<TrackedDevice> devices;
  final Whitelist whitelist;
  final double range;
  final ColorScheme colors;
  final TextStyle text;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final outer = math.max(0.0, size.shortestSide / 2 - 16);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = colors.outlineVariant;
    final taken = <Rect>[];
    canvas.drawLine(centre - Offset(outer, 0), centre + Offset(outer, 0), ring);
    canvas.drawLine(centre - Offset(0, outer), centre + Offset(0, outer), ring);
    for (final metres in rings.where((ring) => ring <= range)) {
      final radius = radiusFor(metres, range, outer);
      canvas.drawCircle(centre, radius, ring);
      final painter = _text('${metres.round()} m', colors.onSurfaceVariant);
      final origin = centre + Offset(-painter.width / 2, -radius - 2 - painter.height);
      painter.paint(canvas, origin);
      taken.add(origin & painter.size);
    }
    canvas.drawCircle(centre, 4, Paint()..color = colors.primary);

    Offset position(TrackedDevice device) =>
        centre + Offset(math.cos(device.angle), math.sin(device.angle)) * radiusFor(device.distance, range, outer);
    int rank(TrackedDevice device) => whitelist.contains(device.address)
        ? 2
        : device.kind.isStable
        ? 0
        : 1;

    // Unlisted stable devices first, then rotating ones, then listed ones; nearest first within each.
    // The first get drawn on top and named first.
    final ranked = [...devices]
      ..sort((a, b) {
        final byRank = rank(a) - rank(b);
        return byRank != 0 ? byRank : a.distance.compareTo(b.distance);
      });
    for (final device in ranked.reversed) {
      final color = switch (rank(device)) {
        0 => colors.error,
        1 => colors.outline,
        _ => colors.primary,
      };
      canvas.drawCircle(position(device), rank(device) == 2 ? 4 : 5.5, Paint()..color = color);
    }
    for (final device in ranked.take(_maxLabels)) {
      final at = position(device);
      final name = deviceLabel(
        label: whitelist[device.address]?.label,
        name: device.name,
        manufacturer: device.manufacturer,
      );
      final painter = _text(name, rank(device) == 2 ? colors.onSurfaceVariant : colors.onSurface);
      // Labels point toward the centre, so they stay inside the rings.
      final dx = at.dx > centre.dx ? -8 - painter.width : 8.0;
      final rect = (at + Offset(dx, -painter.height / 2)) & painter.size;
      if (taken.any((other) => other.overlaps(rect.inflate(2)))) continue;
      painter.paint(canvas, rect.topLeft);
      taken.add(rect);
    }
  }

  TextPainter _text(String value, Color color) => TextPainter(
    text: TextSpan(
      text: value,
      style: text.copyWith(color: color),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: 140);

  @override
  bool shouldRepaint(_RadarPainter old) => true;
}
