import 'dart:math' as math;

import '../../core/api_client.dart';

class DeskKpis {
  DeskKpis.fromJson(Map<String, dynamic> j)
      : vehiclesActive = j['vehicles_active'] as int,
        vehiclesTotal = j['vehicles_total'] as int,
        aboard = j['aboard'] as int,
        onTimePct = j['on_time_pct'] as int,
        alerts = j['alerts'] as int;

  final int vehiclesActive;
  final int vehiclesTotal;
  final int aboard;
  final int onTimePct;
  final int alerts;
}

class DeskAlert {
  DeskAlert.fromJson(Map<String, dynamic> j)
      : title = j['title'] as String,
        detail = j['detail'] as String,
        tone = j['tone'] as String;

  final String title;
  final String detail;
  final String tone;
}

class DeskRoute {
  DeskRoute.fromJson(Map<String, dynamic> j)
      : tripId = j['trip_id'] as int?,
        routeName = j['route_name'] as String,
        directionLabel = j['direction_label'] as String,
        runNo = (j['run_no'] as int?) ?? 1,
        status = j['status'] as String,
        statusLabel = j['status_label'] as String,
        cabName = j['cab_name'] as String? ?? '',
        driverName = j['driver_name'] as String? ?? '',
        finished = j['finished'] as int,
        total = j['total'] as int,
        nextStop = j['next_stop'] as String?,
        nextEta = j['next_eta'] as int?;

  final int? tripId;
  final String routeName;
  final String directionLabel;
  final int runNo;
  final String status;
  final String statusLabel;
  final String cabName;
  final String driverName;
  final int finished;
  final int total;
  final String? nextStop;
  final int? nextEta;
}

class LiveStop {
  LiveStop.fromJson(Map<String, dynamic> j)
      : name = j['name'] as String,
        lat = (j['lat'] as num?)?.toDouble(),
        lng = (j['lng'] as num?)?.toDouble(),
        status = j['status'] as String,
        order = j['order'] as int;

  final String name;
  final double? lat;
  final double? lng;
  final String status;
  final int order;

  bool get hasPin => lat != null && lng != null;
}

class LiveCab {
  LiveCab.fromJson(Map<String, dynamic> j)
      : tripId = j['trip_id'] as int,
        routeName = j['route_name'] as String,
        directionLabel = j['direction_label'] as String,
        cabName = j['cab_name'] as String? ?? '',
        vehicleNo = j['vehicle_no'] as String? ?? '',
        driverName = j['driver_name'] as String? ?? '',
        lat = (j['lat'] as num?)?.toDouble(),
        lng = (j['lng'] as num?)?.toDouble(),
        speedKmh = j['speed_kmh'] as int?,
        stops = [for (final s in j['stops'] as List) LiveStop.fromJson(s as Map<String, dynamic>)];

  final int tripId;
  final String routeName;
  final String directionLabel;
  final String cabName;
  final String vehicleNo;
  final String driverName;
  final double? lat;
  final double? lng;
  final int? speedKmh;
  final List<LiveStop> stops;

  bool get hasFix => lat != null && lng != null;
}

class TransportOverview {
  TransportOverview.fromJson(Map<String, dynamic> j)
      : school = j['school'] as String,
        contact = j['contact'] as String? ?? '',
        kpis = DeskKpis.fromJson(j['kpis'] as Map<String, dynamic>),
        alerts = [for (final a in j['alerts'] as List) DeskAlert.fromJson(a as Map<String, dynamic>)],
        routes = [for (final r in j['routes'] as List) DeskRoute.fromJson(r as Map<String, dynamic>)],
        live = [for (final c in j['live'] as List) LiveCab.fromJson(c as Map<String, dynamic>)];

  final String school;
  final String contact;
  final DeskKpis kpis;
  final List<DeskAlert> alerts;
  final List<DeskRoute> routes;
  final List<LiveCab> live;
}

class RosterChild {
  RosterChild.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        name = j['name'] as String,
        grade = j['grade'] as String,
        routeName = j['route_name'] as String,
        status = j['status'] as String,
        statusLabel = j['status_label'] as String,
        guardian = j['guardian'] as String? ?? '',
        pin = j['pin'] as String?,
        trackUrl = j['track_url'] as String;

  final int id;
  final String name;
  final String grade;
  final String routeName;
  final String status;
  final String statusLabel;
  final String guardian;
  final String? pin;
  final String trackUrl;
}

class Roster {
  Roster.fromJson(Map<String, dynamic> j)
      : children = [for (final c in j['children'] as List) RosterChild.fromJson(c as Map<String, dynamic>)],
        waiting = (j['counts']['waiting'] as int?) ?? 0,
        enRoute = (j['counts']['en_route'] as int?) ?? 0,
        arrived = (j['counts']['arrived'] as int?) ?? 0,
        absent = (j['counts']['absent'] as int?) ?? 0;

  final List<RosterChild> children;
  final int waiting;
  final int enRoute;
  final int arrived;
  final int absent;
}

class DeskMessage {
  DeskMessage.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        name = j['name'] as String,
        kind = j['kind'] as String,
        label = j['label'] as String,
        body = j['body'] as String,
        at = j['at'] as String;

  final int id;
  final String name;
  final String kind;
  final String label;
  final String body;
  final String at;
}

class RouteReport {
  RouteReport.fromJson(Map<String, dynamic> j)
      : name = j['name'] as String,
        trips = j['trips'] as int,
        done = j['done'] as int,
        absent = j['absent'] as int;

  final String name;
  final int trips;
  final int done;
  final int absent;
}

class TransportReport {
  TransportReport.fromJson(Map<String, dynamic> j)
      : from = j['from'] as String,
        to = j['to'] as String,
        trips = j['trips'] as int,
        completed = j['completed'] as int,
        stopsDone = j['stops_done'] as int,
        stopsAbsent = j['stops_absent'] as int,
        sos = j['sos'] as int,
        routes = [for (final r in j['routes'] as List) RouteReport.fromJson(r as Map<String, dynamic>)];

  final String from;
  final String to;
  final int trips;
  final int completed;
  final int stopsDone;
  final int stopsAbsent;
  final int sos;
  final List<RouteReport> routes;
}

class TransportSettings {
  TransportSettings.fromJson(Map<String, dynamic> j)
      : school = j['school'] as String,
        contact = j['contact'] as String? ?? '',
        notifyPickup = j['notify_pickup'] as bool,
        speedAlerts = j['speed_alerts'] as bool,
        deleteCoordinates = j['delete_coordinates'] as bool;

  final String school;
  final String contact;
  final bool notifyPickup;
  final bool speedAlerts;
  final bool deleteCoordinates;
}

class DeskApi {
  DeskApi(this.api);

  final ApiClient api;

  Future<TransportOverview> overview() async =>
      TransportOverview.fromJson(await api.get('transport/overview.php'));

  Future<Roster> roster([String query = '']) async => Roster.fromJson(
        await api.get('transport/roster.php', {if (query.trim().isNotEmpty) 'q': query.trim()}),
      );

  Future<List<DeskMessage>> messages() async {
    final d = await api.get('transport/messages.php');
    return [for (final m in d['messages'] as List) DeskMessage.fromJson(m as Map<String, dynamic>)];
  }

  Future<DeskMessage> send(String body, {String kind = 'message'}) async => DeskMessage.fromJson(
        (await api.post('transport/messages.php', {'body': body, 'kind': kind}))['message'] as Map<String, dynamic>,
      );

  Future<TransportReport> report() async => TransportReport.fromJson(await api.get('transport/reports.php'));

  Future<TransportSettings> settings() async =>
      TransportSettings.fromJson((await api.get('transport/settings.php'))['settings'] as Map<String, dynamic>);

  Future<TransportSettings> saveSettings(TransportSettings current, {String? contact}) async =>
      TransportSettings.fromJson((await api.post('transport/settings.php', {
        'contact': ?contact,
        'notify_pickup': current.notifyPickup,
        'speed_alerts': current.speedAlerts,
        'delete_coordinates': current.deleteCoordinates,
      }))['settings'] as Map<String, dynamic>);
}

String csvCell(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

String rosterCsv(List<RosterChild> children) {
  final lines = <String>['Name,Grade,Route,Status,Guardian'];
  for (final c in children) {
    lines.add([c.name, c.grade, c.routeName, c.statusLabel, c.guardian].map(csvCell).join(','));
  }
  return lines.join('\n');
}

/// Metres between two WGS84 points.
double metersBetween(double lat1, double lng1, double lat2, double lng2) {
  const earth = 6371000.0;
  final p1 = lat1 * math.pi / 180;
  final p2 = lat2 * math.pi / 180;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * earth * math.asin(math.sqrt(a));
}

String approachPhrase(double meters) {
  if (meters < 40) return 'You are at the next stop';
  if (meters < 1000) return 'Next stop is about ${meters.round()} m ahead';
  return 'Next stop is about ${(meters / 1000).toStringAsFixed(1)} km ahead';
}
