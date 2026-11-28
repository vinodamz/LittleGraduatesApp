import '../../core/api_client.dart';

/// One child in "my class" with today's mark (null status = not saved yet).
class ClassChild {
  ClassChild.fromJson(Map<String, dynamic> j)
    : id = (j['id'] as num?)?.toInt() ?? 0,
      name = j['name'] as String? ?? '',
      grade = j['grade'] as String? ?? '',
      status = j['status'] as String?,
      notes = j['notes'] as String?;

  final int id;
  final String name;
  final String grade;
  final String? status;
  final String? notes;
}

class ClassCounts {
  ClassCounts.fromJson(Map<String, dynamic> j)
    : total = (j['total'] as num?)?.toInt() ?? 0,
      unsaved = (j['unsaved'] as num?)?.toInt() ?? 0,
      present = (j['present'] as num?)?.toInt() ?? 0,
      absent = (j['absent'] as num?)?.toInt() ?? 0,
      other = (j['other'] as num?)?.toInt() ?? 0;

  final int total;
  final int unsaved;
  final int present;
  final int absent;
  final int other;
}

class MyClass {
  MyClass.fromJson(Map<String, dynamic> j)
    : counts = ClassCounts.fromJson(
        j['counts'] as Map<String, dynamic>? ?? const {},
      ),
      students = [
        for (final s in j['students'] as List? ?? const [])
          ClassChild.fromJson(s as Map<String, dynamic>),
      ],
      statuses = [
        for (final s
            in j['statuses'] as List? ??
                const ['present', 'absent', 'late', 'excused', 'holiday'])
          s as String,
      ],
      canCover = j['can_cover'] as bool? ?? false;

  final ClassCounts counts;
  final List<ClassChild> students;
  final List<String> statuses;

  /// No class of their own, but may mark any class (subteacher or admin).
  final bool canCover;

  bool get hasClass => students.isNotEmpty;
}

class AdminGlance {
  AdminGlance.fromJson(Map<String, dynamic> j)
    : staffTotal = (j['staff_total'] as num?)?.toInt() ?? 0,
      staffIn = (j['staff_in'] as num?)?.toInt() ?? 0,
      leaveToReview = (j['leave_to_review'] as num?)?.toInt() ?? 0;

  final int staffTotal;
  final int staffIn;
  final int leaveToReview;
}

class TodayLinks {
  TodayLinks.fromJson(Map<String, dynamic> j)
    : myDay = j['my_day'] as String? ?? '',
      attendance = j['attendance'] as String? ?? '',
      duties = j['duties'] as String? ?? '',
      assessment = j['assessment'] as String? ?? '',
      leaveReview = j['leave_review'] as String? ?? '',
      staffToday = j['staff_today'] as String? ?? '';

  final String myDay;
  final String attendance;
  final String duties;
  final String assessment;
  final String leaveReview;
  final String staffToday;
}

/// Everything the Today tab shows beyond check-in, for every role.
class TodaySummary {
  TodaySummary.fromJson(Map<String, dynamic> j)
    : myClass = j['class'] is Map<String, dynamic>
          ? MyClass.fromJson(j['class'] as Map<String, dynamic>)
          : null,
      dutiesPending = (j['duties_pending'] as num?)?.toInt() ?? 0,
      assessmentsPending = (j['assessments_pending'] as num?)?.toInt() ?? 0,
      admin = j['admin'] is Map<String, dynamic>
          ? AdminGlance.fromJson(j['admin'] as Map<String, dynamic>)
          : null,
      links = TodayLinks.fromJson(
        j['links'] as Map<String, dynamic>? ?? const {},
      );

  final MyClass? myClass;
  final int dutiesPending;
  final int assessmentsPending;
  final AdminGlance? admin;
  final TodayLinks links;
}

String classStatusLabel(String status) => switch (status) {
  'present' => 'Present',
  'absent' => 'Absent',
  'late' => 'Late',
  'excused' => 'Excused',
  'holiday' => 'Holiday',
  _ => status,
};

class TodayApi {
  TodayApi(this.api);

  final ApiClient api;

  /// Null when the school server predates this endpoint; Today then simply
  /// shows what it showed before.
  static TodaySummary? _parse(Map<String, dynamic> d) {
    final t = d['today'];
    return t is Map<String, dynamic> ? TodaySummary.fromJson(t) : null;
  }

  Future<TodaySummary?> load() async => _parse(await api.get('today.php'));

  Future<TodaySummary?> markRestPresent() async =>
      _parse(await api.post('class/attendance.php', {'op': 'rest_present'}));

  Future<TodaySummary?> setMark(int studentId, String status) async => _parse(
    await api.post('class/attendance.php', {
      'op': 'set',
      'student_id': studentId,
      'status': status,
    }),
  );
}
