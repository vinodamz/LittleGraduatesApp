import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/notifications.dart';
import 'transport_api.dart';

/// Streams the phone's position to the server while one trip is running.
///
/// On Android this runs as a foreground service (the ongoing "Trip running"
/// notification), so it keeps working while the driver uses WhatsApp or the
/// screen is off. It stops when the trip is finished or cancelled, when the
/// server says the trip is no longer running, or when the driver stops it.
class LocationTracker extends ChangeNotifier {
  LocationTracker(this.api) : transport = TransportApi(api);

  final ApiClient api;
  final TransportApi transport;

  int? tripId;
  String routeName = '';
  Position? lastFix;
  DateTime? lastUploadAt;
  String? problem;

  /// Changes when the server's view of the trip changes (marks, alerts due).
  String? serverSignature;

  StreamSubscription<Position>? _positions;
  Timer? _uploader;
  final List<Map<String, dynamic>> _buffer = [];
  final Set<String> _notified = {};
  bool _uploading = false;

  bool get active => tripId != null;

  /// Asks for location (and, where Android allows, "all the time") and
  /// notification permission. Returns an explanation if tracking can't run.
  Future<String?> ensurePermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Turn on Location in the phone settings, then try again.';
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      return 'Location permission is needed to share the cab with families. Allow it in Settings → Apps → Little Graduates.';
    }
    await Notifications.requestPermission();
    alwaysAllowed = p == LocationPermission.always;
    return null;
  }

  /// The foreground service works with "while using the app", but "all the
  /// time" survives aggressive battery savers better. Android only grants it
  /// from the app's settings page.
  bool alwaysAllowed = false;

  Future<void> openLocationSettings() => Geolocator.openAppSettings();

  Future<String?> start(int id, String name) async {
    if (tripId == id && _positions != null) return null;
    await stop();
    final err = await ensurePermissions();
    if (err != null) {
      problem = err;
      notifyListeners();
      return err;
    }
    tripId = id;
    routeName = name;
    problem = null;
    _notified.clear();

    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            intervalDuration: const Duration(seconds: 5),
            foregroundNotificationConfig: ForegroundNotificationConfig(
              notificationTitle: 'Trip running · $name',
              notificationText: 'Sharing the cab location with families until the trip ends',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
            pauseLocationUpdatesAutomatically: false,
          );

    _positions = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        lastFix = pos;
        _buffer.add({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracy': pos.accuracy,
          'speed': pos.speed,
          'heading': pos.heading,
          't': pos.timestamp.millisecondsSinceEpoch,
        });
        if (_buffer.length > 500) _buffer.removeRange(0, _buffer.length - 500);
        notifyListeners();
      },
      onError: (Object e) {
        problem = 'Location stopped: $e';
        notifyListeners();
      },
    );
    _uploader = Timer.periodic(AppConfig.locationUploadInterval, (_) => upload());
    notifyListeners();
    return null;
  }

  Future<void> stop() async {
    await _positions?.cancel();
    _positions = null;
    _uploader?.cancel();
    _uploader = null;
    if (_buffer.isNotEmpty) await upload();
    _buffer.clear();
    tripId = null;
    lastFix = null;
    notifyListeners();
  }

  Future<void> upload() async {
    final id = tripId;
    if (id == null || _uploading || _buffer.isEmpty) return;
    _uploading = true;
    final batch = List<Map<String, dynamic>>.of(_buffer);
    try {
      final d = await api.post('transport/location.php', {'trip_id': id, 'points': batch});
      _buffer.removeRange(0, batch.length.clamp(0, _buffer.length));
      lastUploadAt = DateTime.now();
      problem = null;
      serverSignature = d['signature'] as String?;
      if (d['status'] != 'running') {
        _uploading = false;
        _buffer.clear();
        await stop();
        return;
      }
      await _notifyFor(
        reached: [for (final x in d['reached'] as List) x as int],
        due: [for (final x in d['due'] as List) x as int],
      );
    } on ApiException catch (e) {
      // Keep the points and try again on the next tick.
      problem = 'Not sent yet — ${e.message}';
    } finally {
      _uploading = false;
      notifyListeners();
    }
  }

  Future<void> _notifyFor({required List<int> reached, required List<int> due}) async {
    final fresh = [
      for (final s in reached) if (!_notified.contains('r$s')) ('r', s),
      for (final s in due) if (!_notified.contains('e$s')) ('e', s),
    ];
    if (fresh.isEmpty || tripId == null) return;
    final trip = await transport.trip(tripId!);
    final byId = {for (final s in trip.stops) s.id: s};
    for (final (kind, id) in fresh) {
      _notified.add('$kind$id');
      final s = byId[id];
      if (s == null || s.parents.isEmpty) continue;
      if (kind == 'r') {
        await Notifications.show(id * 2, 'Reached ${s.firstName}\'s stop',
            'Tap to tell the family on WhatsApp', payload: '$id');
      } else {
        await Notifications.show(id * 2 + 1, '${s.firstName} is about 5 minutes away',
            'Tap to send the 5-minute WhatsApp', payload: '$id');
      }
    }
  }

  @override
  void dispose() {
    _positions?.cancel();
    _uploader?.cancel();
    super.dispose();
  }
}
