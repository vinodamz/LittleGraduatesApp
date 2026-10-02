import '../../core/api_client.dart';

class TripSummary {
  TripSummary.fromJson(Map<String, dynamic> j)
      : routeId = j['route_id'] as int,
        routeName = j['route_name'] as String,
        direction = j['direction'] as String,
        directionLabel = j['direction_label'] as String,
        time = j['time'] as String?,
        cabName = j['cab_name'] as String,
        children = j['children'] as int,
        tripId = j['trip_id'] as int?,
        status = j['status'] as String,
        statusLabel = j['status_label'] as String,
        finished = j['finished'] as int,
        total = j['total'] as int;

  final int routeId;
  final String routeName;
  final String direction;
  final String directionLabel;
  final String? time;
  final String cabName;
  final int children;
  final int? tripId;
  final String status;
  final String statusLabel;
  final int finished;
  final int total;
}

class StopParent {
  StopParent.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        label = j['label'] as String,
        name = j['name'] as String;

  final int id;
  final String label;
  final String name;
}

class TripStop {
  TripStop.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        order = j['order'] as int,
        name = j['name'] as String,
        grade = j['grade'] as String,
        note = j['note'] as String,
        hasLocation = j['location'] != null,
        status = j['status'] as String,
        reachedAt = _date(j['reached_at']),
        doneAt = _date(j['done_at']),
        etaMinutes = j['eta_minutes'] as int?,
        etaAlertSent = j['eta_alert_sent'] as bool,
        reachedAlertSent = j['reached_alert_sent'] as bool,
        etaAlertDue = j['eta_alert_due'] as bool,
        parents = [for (final p in j['parents'] as List) StopParent.fromJson(p as Map<String, dynamic>)];

  final int id;
  final int order;
  final String name;
  final String grade;
  final String note;
  final bool hasLocation;
  final String status;
  final DateTime? reachedAt;
  final DateTime? doneAt;
  final int? etaMinutes;
  final bool etaAlertSent;
  final bool reachedAlertSent;
  final bool etaAlertDue;
  final List<StopParent> parents;

  bool get pending => status == 'pending';
  bool get reached => reachedAt != null;
  String get firstName => name.split(' ').first;
}

class Trip {
  Trip.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        routeName = j['route_name'] as String,
        direction = j['direction'] as String,
        directionLabel = j['direction_label'] as String,
        status = j['status'] as String,
        statusLabel = j['status_label'] as String,
        cabName = (j['cab'] as Map)['name'] as String,
        vehicleNo = (j['cab'] as Map)['vehicle_no'] as String,
        lastLocationAt = _date(j['last_location_at']),
        signature = j['signature'] as String,
        stops = [for (final s in j['stops'] as List) TripStop.fromJson(s as Map<String, dynamic>)];

  final int id;
  final String routeName;
  final String direction;
  final String directionLabel;
  final String status;
  final String statusLabel;
  final String cabName;
  final String vehicleNo;
  final DateTime? lastLocationAt;
  final String signature;
  final List<TripStop> stops;

  bool get running => status == 'running';
  bool get scheduled => status == 'scheduled';
  String get doneVerb => direction == 'drop' ? 'Dropped' : 'Picked up';
  int get pendingCount => stops.where((s) => s.pending).length;
}

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

class TransportApi {
  TransportApi(this.api);

  final ApiClient api;

  Future<List<TripSummary>> today() async {
    final d = await api.get('transport/today.php');
    return [for (final t in d['trips'] as List) TripSummary.fromJson(t as Map<String, dynamic>)];
  }

  Future<Trip> open(int routeId, String direction) async =>
      Trip.fromJson((await api.post('transport/open.php', {'route_id': routeId, 'direction': direction}))['trip']
          as Map<String, dynamic>);

  Future<Trip> trip(int id) async =>
      Trip.fromJson((await api.get('transport/trip.php', {'id': '$id'}))['trip'] as Map<String, dynamic>);

  Future<Trip> action(int tripId, String op, {int? stopId}) async => Trip.fromJson(
      (await api.post('transport/action.php', {'trip_id': tripId, 'op': op, 'stop_id': ?stopId}))['trip']
          as Map<String, dynamic>);

  /// Logs the alert and returns the wa.me link to open.
  Future<String> alertUrl(int stopId, String kind, int parentId) async =>
      (await api.post('transport/alert.php', {'stop_id': stopId, 'kind': kind, 'parent_id': parentId}))['url']
          as String;
}
