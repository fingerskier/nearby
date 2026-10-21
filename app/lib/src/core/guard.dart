import 'settings.dart';
import 'tracker.dart';
import 'whitelist.dart';

/// What [Guard.observe] decided about a sighting.
sealed class GuardEvent {
  const GuardEvent(this.device);

  final TrackedDevice device;
}

/// Learning mode added the device to the whitelist.
final class Learned extends GuardEvent {
  const Learned(super.device);
}

/// An unlisted device came into range: alert.
final class Arrived extends GuardEvent {
  const Arrived(super.device);
}

class _Visit {
  _Visit(this.lastSeen);

  DateTime lastSeen;
  int sightings = 0;
  bool settled = false;
}

/// Decides which sightings are arrivals worth an alert, and fills the whitelist while learning.
///
/// A visit starts with the first sighting after a device has been away for [Settings.awayAfter].
/// Each visit alerts at most once, after [confirmSightings] sightings so a single stray packet stays quiet,
/// and only once the device is within [Settings.alertRadius]. A device that alerted stays quiet for
/// [Settings.reAlertMinutes] even if it leaves and comes back, so one hovering at the edge of range
/// doesn't ping over and over.
class Guard {
  Guard(this.settings, this.whitelist);

  Settings settings;
  final Whitelist whitelist;
  DateTime? _learnUntil;
  final _visits = <String, _Visit>{};
  final _lastAlert = <String, DateTime>{};

  static const confirmSightings = 2;

  DateTime? get learnUntil => _learnUntil;

  bool isLearning(DateTime now) => _learnUntil != null && now.isBefore(_learnUntil!);

  void startLearning(DateTime now) => _learnUntil = now.add(Duration(minutes: settings.learnMinutes));

  void stopLearning() => _learnUntil = null;

  GuardEvent? observe(TrackedDevice device, DateTime now) {
    var visit = _visits[device.address];
    if (visit == null || now.difference(visit.lastSeen) > settings.awayAfter) {
      visit = _visits[device.address] = _Visit(now);
    }
    visit
      ..lastSeen = now
      ..sightings += 1;
    if (visit.sightings < confirmSightings) return null;

    if (isLearning(now)) {
      // Rotating addresses would never match again, so they'd only clutter the list.
      if (!device.kind.isStable) return null;
      return whitelist.add(device.address, name: device.name, at: now) ? Learned(device) : null;
    }

    if (visit.settled || whitelist.contains(device.address)) return null;
    if (!device.kind.isStable && !settings.alertRotating) return null;
    final radius = settings.alertRadius;
    if (radius != null && device.distance > radius) return null;

    visit.settled = true;
    final last = _lastAlert[device.address];
    if (last != null && now.difference(last) < Duration(minutes: settings.reAlertMinutes)) return null;
    _lastAlert[device.address] = now;
    return Arrived(device);
  }

  /// Drops bookkeeping that can no longer affect a decision.
  void prune(DateTime now) {
    _visits.removeWhere((_, visit) => now.difference(visit.lastSeen) > settings.awayAfter);
    _lastAlert.removeWhere((_, at) => now.difference(at) >= Duration(minutes: settings.reAlertMinutes));
  }
}
