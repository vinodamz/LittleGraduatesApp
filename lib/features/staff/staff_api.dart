import '../../core/api_client.dart';

class StaffLink {
  StaffLink.fromJson(Map<String, dynamic> j)
      : staff = j['staff'] as String? ?? '',
        attendance = j['attendance'] as String? ?? '',
        leave = j['leave'] as String? ?? '',
        duties = j['duties'] as String? ?? '';

  final String staff;
  final String attendance;
  final String leave;
  final String duties;
}

class StaffAttendance {
  StaffAttendance.fromJson(Map<String, dynamic> j)
      : status = j['status'] as String?,
        statusLabel = j['status_label'] as String? ?? 'Not checked in',
        checkIn = j['check_in'] as String?,
        checkOut = j['check_out'] as String?,
        shiftLabel = j['shift_label'] as String? ?? '',
        lateAfter = j['late_after'] as String?;

  final String? status;
  final String statusLabel;
  final String? checkIn;
  final String? checkOut;
  final String shiftLabel;
  final String? lateAfter;

  bool get checkedIn => checkIn != null && checkIn!.isNotEmpty;
  bool get checkedOut => checkOut != null && checkOut!.isNotEmpty;
}

class LeaveTypeOption {
  LeaveTypeOption.fromJson(Map<String, dynamic> j)
      : key = j['key'] as String? ?? 'casual',
        label = j['label'] as String? ?? 'Casual';

  final String key;
  final String label;
}

class LeaveRequest {
  LeaveRequest.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int? ?? 0,
        type = j['type'] as String? ?? '',
        typeLabel = j['type_label'] as String? ?? '',
        startDate = j['start_date'] as String? ?? '',
        endDate = j['end_date'] as String? ?? '',
        halfDay = j['half_day'] as String? ?? '',
        days = (j['days'] as num?)?.toDouble() ?? 0,
        daysLabel = j['days_label'] as String? ?? '',
        reason = j['reason'] as String? ?? '',
        status = j['status'] as String? ?? '',
        statusLabel = j['status_label'] as String? ?? '';

  final int id;
  final String type;
  final String typeLabel;
  final String startDate;
  final String endDate;
  final String halfDay;
  final double days;
  final String daysLabel;
  final String reason;
  final String status;
  final String statusLabel;

  bool get pending => status == 'pending';
}

class StaffLeave {
  StaffLeave.fromJson(Map<String, dynamic> j)
      : balance = (j['balance'] as num?)?.toDouble() ?? 0,
        balanceLabel = j['balance_label'] as String? ?? '',
        pending = j['pending'] as int? ?? 0,
        pendingReviews = j['pending_reviews'] as int? ?? 0,
        types = [
          for (final t in (j['types'] as List? ?? const []))
            LeaveTypeOption.fromJson(t as Map<String, dynamic>),
        ],
        requests = [
          for (final r in (j['requests'] as List? ?? const []))
            LeaveRequest.fromJson(r as Map<String, dynamic>),
        ];

  final double balance;
  final String balanceLabel;
  final int pending;
  final int pendingReviews;
  final List<LeaveTypeOption> types;
  final List<LeaveRequest> requests;
}

class RosterPerson {
  RosterPerson.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int? ?? 0,
        name = j['name'] as String? ?? '',
        roleLabel = j['role_label'] as String? ?? '',
        status = j['status'] as String?,
        statusLabel = j['status_label'] as String? ?? 'Not in yet',
        checkIn = j['check_in'] as String?,
        checkOut = j['check_out'] as String?;

  final int id;
  final String name;
  final String roleLabel;
  final String? status;
  final String statusLabel;
  final String? checkIn;
  final String? checkOut;

  bool get waiting => checkIn == null || checkIn!.isEmpty;
  bool get here => !waiting && (checkOut == null || checkOut!.isEmpty);
}

class StaffDay {
  StaffDay.fromJson(Map<String, dynamic> j)
      : date = j['date'] as String? ?? '',
        dateLabel = j['date_label'] as String? ?? '',
        isAdmin = j['is_admin'] as bool? ?? false,
        attendance = StaffAttendance.fromJson((j['attendance'] as Map?)?.cast<String, dynamic>() ?? const {}),
        leave = j['leave'] == null ? null : StaffLeave.fromJson((j['leave'] as Map).cast<String, dynamic>()),
        dutiesPending = j['duties_pending'] as int? ?? 0,
        roster = [
          for (final p in (j['roster'] as List? ?? const []))
            RosterPerson.fromJson(p as Map<String, dynamic>),
        ],
        links = StaffLink.fromJson((j['links'] as Map?)?.cast<String, dynamic>() ?? const {});

  final String date;
  final String dateLabel;
  final bool isAdmin;
  final StaffAttendance attendance;
  final StaffLeave? leave;
  final int dutiesPending;
  final List<RosterPerson> roster;
  final StaffLink links;
}

class LeaveResult {
  LeaveResult(this.message, this.notice, this.day);

  final String message;
  final String notice;
  final StaffDay day;
}

class StaffApi {
  StaffApi(this.api);

  final ApiClient api;

  Future<StaffDay> today() async {
    final d = await api.get('staff/today.php');
    return StaffDay.fromJson(d['day'] as Map<String, dynamic>);
  }

  Future<StaffDay> check(String op) async {
    final d = await api.post('staff/check.php', {'op': op});
    return StaffDay.fromJson(d['day'] as Map<String, dynamic>);
  }

  Future<LeaveResult> leave(Map<String, dynamic> body) async {
    final d = await api.post('staff/leave.php', body);
    return LeaveResult(
      d['message'] as String? ?? 'Saved.',
      d['notice'] as String? ?? '',
      StaffDay.fromJson(d['day'] as Map<String, dynamic>),
    );
  }
}
