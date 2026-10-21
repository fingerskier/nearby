import 'dart:math' as math;

/// Scalar Kalman filter for a slowly drifting signal such as RSSI in dB.
/// Process noise accrues with elapsed time, so irregular advertising intervals are handled.
class Kalman1D {
  /// [q] is process noise, dB² per second: how fast the true value may drift.
  /// [r] is measurement noise, dB²: the variance of a single reading.
  Kalman1D(this.q, this.r);

  double q;
  double r;
  double _x = double.nan;
  double _p = 0;
  DateTime? _lastAt;

  double get value => _x;

  double update(double z, DateTime at) {
    final lastAt = _lastAt;
    _lastAt = at;
    if (lastAt == null) {
      _x = z;
      _p = r;
      return z;
    }
    final dt = math.max(0, at.difference(lastAt).inMicroseconds / 1e6);
    final prior = _p + q * dt;
    final gain = prior / (prior + r);
    _x += gain * (z - _x);
    _p = (1 - gain) * prior;
    return _x;
  }
}
