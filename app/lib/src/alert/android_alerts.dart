import 'package:flutter/services.dart';

import '../android_channel.dart';
import 'notifier.dart';
import 'pinger.dart';

/// Notifications posted by the app's plugin (Alerts.kt). Buttons and dismissals come back as events, even
/// while the app is in the background.
class AndroidNotifier implements Notifier {
  AndroidNotifier(this._channel);

  final AndroidChannel _channel;

  @override
  late final Stream<NoticeAction> actions = _channel
      .eventsOf('action')
      .map((event) => NoticeAction(event['id']! as int, event['key'] as String? ?? ''));

  @override
  late final Stream<int> closed = _channel.eventsOf('dismissed').map((event) => event['id']! as int);

  /// Null when the user has turned the app's notifications off.
  @override
  Future<int?> show(Notice notice) async {
    try {
      return await _channel.invoke<int>('notify', {
        'title': notice.summary,
        'body': notice.body,
        'actions': notice.actions,
      });
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> allowed() async => await _channel.invoke<bool>('notificationsAllowed') ?? true;

  @override
  Future<void> requestAccess() => _channel.invoke<bool>('requestNotifications');

  @override
  Future<void> close() async {}
}

/// Plays the phone's notification sound.
class AndroidPinger implements Pinger {
  AndroidPinger(this._channel);

  final AndroidChannel _channel;

  @override
  Future<bool> ping() async {
    try {
      return await _channel.invoke<bool>('ping') ?? false;
    } on PlatformException {
      return false;
    }
  }
}
