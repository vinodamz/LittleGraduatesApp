import '../../core/session.dart';

const schoolGroups = {
  'Daily work': [
    'my_day',
    'duties',
    'tasks',
    'materials',
    'plans',
    'staff',
    'my_leave',
    'notifications',
  ],
  'Children': ['students', 'montessori', 'daycare', 'logbook'],
  'School office': [
    'transport',
    'crm',
    'recruitment',
    'fees',
    'expenses',
    'money',
    'inventory',
    'wacrm',
  ],
  'Administration': [
    'duties_admin',
    'feedback',
    'surveys',
    'grades',
    'admin',
    'mcp_admin',
    'n8n',
  ],
};

Map<String, List<AppModule>> groupSchoolModules(List<AppModule> modules) {
  final result = <String, List<AppModule>>{};
  final remaining = {for (final module in modules) module.key: module};
  for (final group in schoolGroups.entries) {
    final items = <AppModule>[];
    for (final key in group.value) {
      final module = remaining.remove(key);
      if (module != null) items.add(module);
    }
    if (items.isNotEmpty) result[group.key] = items;
  }
  if (remaining.isNotEmpty) result['Other tools'] = remaining.values.toList();
  return result;
}

List<AppModule> dailyShortcuts(List<AppModule> modules) {
  final byKey = {for (final module in modules) module.key: module};
  return [
    for (final key in [
      'duties',
      'materials',
      'my_day',
      'tasks',
      'plans',
      'my_leave',
      'students',
    ])
      if (byKey[key] != null) byKey[key]!,
  ].take(4).toList();
}
