import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Driver prompts ("Riya is ~5 min away — tap to WhatsApp"). Tapping one
/// reopens the app; the payload is the trip-stop id so the trip screen can
/// scroll to it.
class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static final _taps = StreamController<String>.broadcast();

  static Stream<String> get taps => _taps.stream;

  static const _channel = AndroidNotificationDetails(
    'trip_alerts',
    'Trip alerts',
    channelDescription: 'When a family is about 5 minutes away or the cab has reached them',
    importance: Importance.high,
    priority: Priority.high,
  );

  static Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload != null) _taps.add(r.payload!);
      },
    );
  }

  static Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> show(int id, String title, String body, {String? payload}) => _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: _channel, iOS: DarwinNotificationDetails()),
        payload: payload,
      );
}
