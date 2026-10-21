import 'dart:math' as math;

/// Log-distance path-loss model: rssi = ref1m − 10·n·log10(d).
class PathLoss {
  const PathLoss({required this.ref1m, required this.n});

  /// Expected RSSI at 1 m, dBm.
  final double ref1m;

  /// Path-loss exponent: ~2 in open space, 2.5–4 indoors and through obstacles.
  final double n;
}

/// Converts an advertised TX power (dBm at the antenna) to an RSSI-at-1 m reference:
/// free-space loss at 1 m on 2.4 GHz is ~40 dB, plus ~1 dB of receiver/body loss.
const txPowerToRef1m = 41;

/// Estimates are clamped to this range; beyond it the model says nothing useful.
const minDistance = 0.1;
const maxDistance = 100.0;

double distanceFromRssi(double rssi, PathLoss model) {
  final d = math.pow(10, (model.ref1m - rssi) / (10 * model.n)).toDouble();
  return d.clamp(minDistance, maxDistance);
}

double rssiAtDistance(double distance, PathLoss model) => model.ref1m - 10 * model.n * math.log(distance) / math.ln10;

/// The 1 m reference for one device: a per-device calibration wins, then advertised TX power, then the default.
double resolveRef1m({double? calibrated, int? txPower, required bool useTxPower, required double fallback}) {
  if (calibrated != null) return calibrated;
  if (useTxPower && txPower != null) return (txPower - txPowerToRef1m).toDouble();
  return fallback;
}
