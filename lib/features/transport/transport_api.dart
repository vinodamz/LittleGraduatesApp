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
        runNo = (j['run_no'] as int?) ?? 1,
        canStartAnother = j['can_start_another'] as bool? ?? false,
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
  final int runNo;
  final bool canStartAnother;
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
        lat = _coord(j['location'], 'lat'),
        lng = _coord(j['location'], 'lng'),
        pin = j['pin'] as String?,
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
  final double? lat;
  final double? lng;
  final String? pin;
  final String status;
  final DateTime? reachedAt;
  final DateTime? doneAt;
  final int? etaMinutes;
  final bool etaAlertSent;
  final bool reachedAlertSent;
  final bool etaAlertDue;
  final List<StopParent> parents;

  bool get hasLocation => lat != null && lng != null;
  bool get pending => status == 'pending';
  bool get reached => reachedAt != null;
  String get firstName => name.split(' ').first;
}

class Trip {
  Trip.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        routeId = j['route_id'] as int,
        runNo = (j['run_no'] as int?) ?? 1,
        routeName = j['route_name'] as String,
        direction = j['direction'] as String,
        directionLabel = j['direction_label'] as String,
        status = j['status'] as String,
        statusLabel = j['status_label'] as String,
        cabName = (j['cab'] as Map)['name'] as String,
        vehicleNo = (j['cab'] as Map)['vehicle_no'] as String,
        startedAt = _date(j['started_at']),
        lastLocationAt = _date(j['last_location_at']),
        speedKmh = (j['position'] is Map) ? (j['position']['speed_kmh'] as int?) : null,
        signature = j['signature'] as String,
        stops = [for (final s in j['stops'] as List) TripStop.fromJson(s as Map<String, dynamic>)];

  final int id;
  final int routeId;
  final int runNo;
  final String routeName;
  final String direction;
  final String directionLabel;
  final String status;
  final String statusLabel;
  final String cabName;
  final String vehicleNo;
  final DateTime? startedAt;
  final DateTime? lastLocationAt;
  final int? speedKmh;
  final String signature;
  final List<TripStop> stops;

  bool get running => status == 'running';
  bool get scheduled => status == 'scheduled';
  String get doneVerb => direction == 'drop' ? 'Dropped' : 'Picked up';
  int get pendingCount => stops.where((s) => s.pending).length;
}

class RouteOption {
  RouteOption.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        name = j['name'] as String,
        cabName = j['cab_name'] as String,
        children = j['children'] as int,
        directions = [for (final d in j['directions'] as List) d as String],
        pickupTime = j['pickup_time'] as String?,
        dropTime = j['drop_time'] as String?;

  final int id;
  final String name;
  final String cabName;
  final int children;
  final List<String> directions;
  final String? pickupTime;
  final String? dropTime;

  bool runs(String direction) => directions.contains(direction);
}

class DayMark {
  DayMark.fromJson(Map<String, dynamic> j)
      : date = j['date'] as String,
        running = j['running'] as int,
        scheduled = j['scheduled'] as int,
        completed = j['completed'] as int,
        cancelled = j['cancelled'] as int;

  final String date;
  final int running;
  final int scheduled;
  final int completed;
  final int cancelled;

  bool get hasTrip => running + scheduled + completed + cancelled > 0;
}

class ChildOption {
  ChildOption.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        name = j['name'] as String,
        grade = j['grade'] as String;

  final int id;
  final String name;
  final String grade;
}

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

double? _coord(Object? location, String key) {
  if (location is! Map) return null;
  final v = location[key];
  return v is num ? v.toDouble() : null;
}

class TransportApi {
  TransportApi(this.api);

  final ApiClient api;

  Future<List<TripSummary>> today([String? date]) async {
    final d = await api.get('transport/today.php', {'date': ?date});
    return [for (final t in d['trips'] as List) TripSummary.fromJson(t as Map<String, dynamic>)];
  }

  Future<List<DayMark>> month(DateTime month) async {
    final key = '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    final d = await api.get('transport/calendar.php', {'month': key});
    return [for (final day in d['days'] as List) DayMark.fromJson(day as Map<String, dynamic>)];
  }

  Future<Trip> open(int routeId, String direction, {String? date}) async =>
      Trip.fromJson((await api.post('transport/open.php', {
        'route_id': routeId,
        'direction': direction,
        'date': ?date,
      }))['trip'] as Map<String, dynamic>);

  Future<Trip> trip(int id) async =>
      Trip.fromJson((await api.get('transport/trip.php', {'id': '$id'}))['trip'] as Map<String, dynamic>);

  Future<Trip> action(
    int tripId,
    String op, {
    int? stopId,
    int? routeId,
    int? studentId,
    double? lat,
    double? lng,
  }) async =>
      Trip.fromJson((await api.post('transport/action.php', {
        'trip_id': tripId,
        'op': op,
        'stop_id': ?stopId,
        'route_id': ?routeId,
        'student_id': ?studentId,
        'lat': ?lat,
        'lng': ?lng,
      }))['trip'] as Map<String, dynamic>);

  Future<List<RouteOption>> routes() async {
    final d = await api.get('transport/routes.php');
    return [for (final r in d['routes'] as List) RouteOption.fromJson(r as Map<String, dynamic>)];
  }

  Future<List<ChildOption>> children([String query = '']) async {
    final d = await api.get('transport/children.php', {if (query.trim().isNotEmpty) 'q': query.trim()});
    return [for (final c in d['children'] as List) ChildOption.fromJson(c as Map<String, dynamic>)];
  }

  /// Another run of a saved route, or a brand-new route when [name] is set.
  Future<Trip> create({
    int? routeId,
    required String direction,
    String? name,
    List<int> studentIds = const [],
    String? date,
  }) async =>
      Trip.fromJson((await api.post('transport/create.php', {
        'direction': direction,
        'route_id': ?routeId,
        'name': ?name,
        'date': ?date,
        if (studentIds.isNotEmpty) 'student_ids': studentIds,
      }))['trip'] as Map<String, dynamic>);

  /// Tells the school desk. Includes a map link when this cab is live.
  Future<void> sos(int tripId, {String note = ''}) async {
    await api.post('transport/sos.php', {'trip_id': tripId, if (note.isNotEmpty) 'note': note});
  }

  /// Logs the alert and returns the wa.me link to open.
  Future<String> alertUrl(int stopId, String kind, int parentId) async =>
      (await api.post('transport/alert.php', {'stop_id': stopId, 'kind': kind, 'parent_id': parentId}))['url']
          as String;
}
