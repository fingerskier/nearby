import 'dart:async';

import 'package:async/async.dart';
import 'package:dbus/dbus.dart';

class Notice {
  const Notice({required this.summary, required this.body, this.actions = const {}});

  final String summary;
  final String body;

  /// Action key → button label.
  final Map<String, String> actions;
}

class NoticeAction {
  const NoticeAction(this.id, this.key);

  final int id;
  final String key;
}

abstract interface class Notifier {
  /// Buttons pressed on notifications, from any app; match them by id.
  Stream<NoticeAction> get actions;

  /// Ids of notifications that are gone: expired, dismissed, or lost when the notification server restarted.
  Stream<int> get closed;

  /// Shows [notice] and returns its id, or null if no notification server answered.
  Future<int?> show(Notice notice);

  /// False when the user has turned this app's notifications off (Android).
  Future<bool> allowed();

  /// Asks the user to turn notifications on: the permission dialog, or the system's settings page.
  Future<void> requestAccess();

  Future<void> close();
}

const _name = 'org.freedesktop.Notifications';

/// Desktop notifications over the freedesktop D-Bus API (mako, dunst, swaync, GNOME, KDE, …).
class DesktopNotifier implements Notifier {
  DesktopNotifier({DBusClient? bus, this.appName = 'nearby', this.desktopEntry = 'io.github.fingerskier.nearby'})
    : _bus = bus ?? DBusClient.session(),
      _ownsBus = bus == null;

  final DBusClient _bus;
  final bool _ownsBus;
  final String appName;
  final String desktopEntry;
  late final _object = DBusRemoteObject(_bus, name: _name, path: DBusObjectPath('/org/freedesktop/Notifications'));
  Future<bool>? _markup;
  final _shown = <int>{};

  @override
  late final Stream<NoticeAction> actions = DBusRemoteObjectSignalStream(
    object: _object,
    interface: _name,
    name: 'ActionInvoked',
    signature: DBusSignature('us'),
  ).map((signal) => NoticeAction(signal.values[0].asUint32(), signal.values[1].asString()));

  @override
  late final Stream<int> closed = StreamGroup.merge([
    DBusRemoteObjectSignalStream(
      object: _object,
      interface: _name,
      name: 'NotificationClosed',
      signature: DBusSignature('uu'),
    ).map((signal) => signal.values[0].asUint32()).where(_shown.remove),
    // A restarted server forgets every notification, and its ids start over.
    _bus.nameOwnerChanged.where((event) => event.name == _name).expand((_) {
      final gone = _shown.toList();
      _shown.clear();
      return gone;
    }),
  ]).asBroadcastStream();

  @override
  Future<int?> show(Notice notice) async {
    try {
      final markup = await (_markup ??= _supportsMarkup());
      final result = await _object.callMethod(_name, 'Notify', [
        DBusString(appName),
        const DBusUint32(0),
        const DBusString('bluetooth'),
        DBusString(notice.summary),
        DBusString(markup ? escapeMarkup(notice.body) : notice.body),
        DBusArray.string([
          for (final MapEntry(:key, :value) in notice.actions.entries) ...[key, value],
        ]),
        DBusDict.stringVariant({
          'urgency': const DBusByte(1),
          'category': const DBusString('device.added'),
          'desktop-entry': DBusString(desktopEntry),
        }),
        const DBusInt32(-1),
      ], replySignature: DBusSignature('u'));
      final id = result.returnValues.first.asUint32();
      _shown.add(id);
      return id;
    } on DBusMethodResponseException {
      return null;
    }
  }

  /// The desktop shows whatever the server accepts; there is nothing to allow.
  @override
  Future<bool> allowed() async => true;

  @override
  Future<void> requestAccess() async {}

  Future<bool> _supportsMarkup() async {
    try {
      final result = await _object.callMethod(_name, 'GetCapabilities', const [], replySignature: DBusSignature('as'));
      return result.returnValues.first.asStringArray().contains('body-markup');
    } on DBusMethodResponseException {
      return false;
    }
  }

  @override
  Future<void> close() async {
    if (_ownsBus) await _bus.close();
  }
}

/// Servers that support body markup parse a small subset of HTML, so device names must be escaped.
String escapeMarkup(String text) => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
