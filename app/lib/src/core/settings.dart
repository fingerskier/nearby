import 'dart:math' as math;

/// Inclusive bounds and slider step for a numeric setting.
class Limit {
  const Limit(this.min, this.max, this.step);

  final double min;
  final double max;
  final double step;

  /// Steps between [min] and [max], for slider divisions.
  int get divisions => ((max - min) / step).round();
}

const _keep = Object();

class Settings {
  const Settings({
    this.n = 2,
    this.ref1m = -59,
    this.useTxPower = true,
    this.noiseDb = 4,
    this.outOfRangeSeconds = 60,
    this.calibrations = const {},
    this.ping = true,
    this.notify = true,
    this.alertRotating = false,
    this.alertRadius,
    this.reAlertMinutes = 30,
    this.includeClassic = false,
    this.scanOnSeconds = 10,
    this.scanOffSeconds = 0,
    this.learnMinutes = 2,
  });

  /// Path-loss exponent.
  final double n;

  /// Default RSSI at 1 m, dBm, for devices without calibration or TX power.
  final double ref1m;

  /// Derive the 1 m reference from advertised TX power when present.
  final bool useTxPower;

  /// Standard deviation of a single RSSI reading, dB; higher smooths more.
  final double noiseDb;

  /// A device not heard from for this long has left (see [awayAfter]).
  final int outOfRangeSeconds;

  /// Per-device 1 m reference, dBm, keyed by address.
  final Map<String, double> calibrations;

  /// Play a sound when an unlisted device arrives.
  final bool ping;

  /// Show a desktop notification when an unlisted device arrives.
  final bool notify;

  /// Also alert on devices whose address rotates; they can't be whitelisted, so this alerts on every rotation.
  final bool alertRotating;

  /// Only alert on devices estimated within this many metres; null alerts at any distance.
  final double? alertRadius;

  /// After alerting on a device, stay quiet about it for this long even if it leaves and returns.
  final int reAlertMinutes;

  /// Also run Bluetooth Classic inquiry; slower, and only finds Classic devices that are discoverable.
  final bool includeClassic;

  /// With [scanOffSeconds] > 0, scan for this long, then rest.
  final int scanOnSeconds;

  /// Rest between scans; 0 scans continuously.
  final int scanOffSeconds;

  /// How long learning mode whitelists everything it sees.
  final int learnMinutes;

  static const nLimit = Limit(1.5, 5, 0.1);
  static const ref1mLimit = Limit(-100, -20, 1);
  static const noiseDbLimit = Limit(1, 12, 0.5);
  static const outOfRangeLimit = Limit(10, 600, 10);
  static const alertRadiusLimit = Limit(0.5, 50, 0.5);
  static const reAlertLimit = Limit(1, 240, 1);
  static const scanOnLimit = Limit(5, 120, 5);
  static const scanOffLimit = Limit(0, 600, 5);
  static const learnLimit = Limit(1, 60, 1);

  /// Process noise for the RSSI filter, dB²/s: lets the estimate follow a walking-pace change in a few seconds.
  static const processNoise = 1.0;

  bool get continuous => scanOffSeconds == 0;

  /// How long a device must go unheard before it counts as gone. Never shorter than a full scan cycle,
  /// so a resting scanner doesn't make everything leave and arrive again.
  Duration get awayAfter {
    final cycle = continuous ? 0 : scanOnSeconds + scanOffSeconds + 5;
    return Duration(seconds: math.max(outOfRangeSeconds, cycle));
  }

  Settings copyWith({
    double? n,
    double? ref1m,
    bool? useTxPower,
    double? noiseDb,
    int? outOfRangeSeconds,
    Map<String, double>? calibrations,
    bool? ping,
    bool? notify,
    bool? alertRotating,
    Object? alertRadius = _keep,
    int? reAlertMinutes,
    bool? includeClassic,
    int? scanOnSeconds,
    int? scanOffSeconds,
    int? learnMinutes,
  }) {
    return Settings(
      n: n ?? this.n,
      ref1m: ref1m ?? this.ref1m,
      useTxPower: useTxPower ?? this.useTxPower,
      noiseDb: noiseDb ?? this.noiseDb,
      outOfRangeSeconds: outOfRangeSeconds ?? this.outOfRangeSeconds,
      calibrations: calibrations ?? this.calibrations,
      ping: ping ?? this.ping,
      notify: notify ?? this.notify,
      alertRotating: alertRotating ?? this.alertRotating,
      alertRadius: identical(alertRadius, _keep) ? this.alertRadius : alertRadius as double?,
      reAlertMinutes: reAlertMinutes ?? this.reAlertMinutes,
      includeClassic: includeClassic ?? this.includeClassic,
      scanOnSeconds: scanOnSeconds ?? this.scanOnSeconds,
      scanOffSeconds: scanOffSeconds ?? this.scanOffSeconds,
      learnMinutes: learnMinutes ?? this.learnMinutes,
    );
  }

  Map<String, Object?> toJson() => {
    'n': n,
    'ref1m': ref1m,
    'useTxPower': useTxPower,
    'noiseDb': noiseDb,
    'outOfRangeSeconds': outOfRangeSeconds,
    'calibrations': calibrations,
    'ping': ping,
    'notify': notify,
    'alertRotating': alertRotating,
    'alertRadius': alertRadius,
    'reAlertMinutes': reAlertMinutes,
    'includeClassic': includeClassic,
    'scanOnSeconds': scanOnSeconds,
    'scanOffSeconds': scanOffSeconds,
    'learnMinutes': learnMinutes,
  };

  /// Accepts anything (e.g. decoded JSON from disk) and returns valid settings, falling back per field.
  static Settings fromJson(Object? raw) {
    final input = raw is Map ? raw : const {};
    const defaults = Settings();
    double number(String key, Limit limit, double fallback) {
      final value = input[key];
      if (value is! num || !value.isFinite) return fallback;
      return value.toDouble().clamp(limit.min, limit.max);
    }

    int whole(String key, Limit limit, int fallback) => number(key, limit, fallback.toDouble()).round();
    bool flag(String key, bool fallback) => input[key] is bool ? input[key] as bool : fallback;

    final calibrations = <String, double>{};
    final rawCalibrations = input['calibrations'];
    if (rawCalibrations is Map) {
      rawCalibrations.forEach((key, value) {
        if (key is String && value is num && value.isFinite) calibrations[key] = value.toDouble();
      });
    }
    final radius = input['alertRadius'];
    return Settings(
      n: number('n', nLimit, defaults.n),
      ref1m: number('ref1m', ref1mLimit, defaults.ref1m),
      useTxPower: flag('useTxPower', defaults.useTxPower),
      noiseDb: number('noiseDb', noiseDbLimit, defaults.noiseDb),
      outOfRangeSeconds: whole('outOfRangeSeconds', outOfRangeLimit, defaults.outOfRangeSeconds),
      calibrations: calibrations,
      ping: flag('ping', defaults.ping),
      notify: flag('notify', defaults.notify),
      alertRotating: flag('alertRotating', defaults.alertRotating),
      alertRadius: radius is num && radius.isFinite
          ? radius.toDouble().clamp(alertRadiusLimit.min, alertRadiusLimit.max)
          : null,
      reAlertMinutes: whole('reAlertMinutes', reAlertLimit, defaults.reAlertMinutes),
      includeClassic: flag('includeClassic', defaults.includeClassic),
      scanOnSeconds: whole('scanOnSeconds', scanOnLimit, defaults.scanOnSeconds),
      scanOffSeconds: whole('scanOffSeconds', scanOffLimit, defaults.scanOffSeconds),
      learnMinutes: whole('learnMinutes', learnLimit, defaults.learnMinutes),
    );
  }
}
