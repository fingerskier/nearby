import 'dart:math' as math;

/// Range rings, metres. The radar's outer edge is always one of these.
const rings = <double>[1, 2, 5, 10, 20, 50, 100];

const _minRange = 2.0;

/// Outer range for the radar: grows as soon as a device falls outside it, but only shrinks once
/// everything fits well inside the next ring down, so the scale doesn't flicker with noisy estimates.
double nextRange(double current, double farthest) {
  final fit = rings.firstWhere((ring) => ring >= math.max(_minRange, farthest), orElse: () => rings.last);
  if (fit >= current) return fit;
  final smaller = rings.where((ring) => ring < current);
  final below = smaller.isEmpty ? fit : smaller.last;
  return farthest < below * 0.8 ? math.max(fit, below) : current;
}

/// Logarithmic radius, so near devices stay apart while far ones still fit on screen.
double radiusFor(double distance, double range, double outer) =>
    outer * _log1p(math.min(distance, range)) / _log1p(range);

double _log1p(double x) => math.log(1 + x);
