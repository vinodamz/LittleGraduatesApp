import '../../core/api_client.dart';

class MaterialCondition {
  MaterialCondition({required this.code, required this.label, required this.tone});

  factory MaterialCondition.fromJson(Map<String, dynamic> j) => MaterialCondition(
        code: j['code'] as String? ?? '',
        label: j['label'] as String? ?? '',
        tone: j['tone'] as String? ?? '',
      );

  final String code;
  final String label;
  final String tone;

  Map<String, dynamic> toJson() => {'code': code, 'label': label, 'tone': tone};
}

class MaterialCheck {
  MaterialCheck({
    required this.id,
    required this.conditionCode,
    required this.label,
    required this.tone,
    required this.notes,
    required this.by,
    required this.at,
  });

  factory MaterialCheck.fromJson(Map<String, dynamic> j) => MaterialCheck(
        id: j['id'] as int? ?? 0,
        conditionCode: j['condition_code'] as String? ?? '',
        label: j['label'] as String? ?? '',
        tone: j['tone'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        by: j['by'] as String? ?? '',
        at: j['at'] as String? ?? '',
      );

  final int id;
  final String conditionCode;
  final String label;
  final String tone;
  final String notes;
  final String by;
  final String at;

  Map<String, dynamic> toJson() => {
        'id': id,
        'condition_code': conditionCode,
        'label': label,
        'tone': tone,
        'notes': notes,
        'by': by,
        'at': at,
      };
}

class MaterialMedia {
  MaterialMedia({required this.id, required this.kind, required this.name, required this.url, this.thumbUrl});

  factory MaterialMedia.fromJson(Map<String, dynamic> j) => MaterialMedia(
        id: j['id'] as int? ?? 0,
        kind: j['kind'] as String? ?? 'photo',
        name: j['name'] as String? ?? '',
        url: j['url'] as String? ?? '',
        thumbUrl: j['thumb_url'] as String?,
      );

  final int id;
  final String kind;
  final String name;
  final String url;
  final String? thumbUrl;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'name': name,
        'url': url,
        if (thumbUrl != null) 'thumb_url': thumbUrl,
      };
}

class MaterialItem {
  MaterialItem({
    required this.id,
    required this.name,
    required this.location,
    required this.sortOrder,
    required this.check,
    required this.media,
  });

  factory MaterialItem.fromJson(Map<String, dynamic> j) => MaterialItem(
        id: j['id'] as int? ?? 0,
        name: j['name'] as String? ?? '',
        location: j['location'] as String? ?? '',
        sortOrder: j['sort_order'] as int? ?? 0,
        check: j['check'] == null ? null : MaterialCheck.fromJson((j['check'] as Map).cast<String, dynamic>()),
        media: [
          for (final m in (j['media'] as List? ?? const []))
            MaterialMedia.fromJson((m as Map).cast<String, dynamic>()),
        ],
      );

  final int id;
  final String name;
  final String location;
  final int sortOrder;
  final MaterialCheck? check;
  final List<MaterialMedia> media;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'location': location,
        'sort_order': sortOrder,
        'check': check?.toJson(),
        'media': [for (final m in media) m.toJson()],
      };
}

class MaterialsSummary {
  MaterialsSummary({
    required this.checked,
    required this.pending,
    required this.total,
    required this.good,
    required this.attention,
    required this.damaged,
    required this.notes,
  });

  factory MaterialsSummary.fromJson(Map<String, dynamic> j) => MaterialsSummary(
        checked: j['checked'] as int? ?? 0,
        pending: j['pending'] as int? ?? 0,
        total: j['total'] as int? ?? 0,
        good: j['good'] as int? ?? 0,
        attention: j['attention'] as int? ?? 0,
        damaged: j['damaged'] as int? ?? 0,
        notes: j['notes'] as int? ?? 0,
      );

  final int checked;
  final int pending;
  final int total;
  final int good;
  final int attention;
  final int damaged;
  final int notes;

  Map<String, dynamic> toJson() => {
        'checked': checked,
        'pending': pending,
        'total': total,
        'good': good,
        'attention': attention,
        'damaged': damaged,
        'notes': notes,
      };
}

class MaterialsLinks {
  MaterialsLinks({
    required this.history,
    required this.trends,
    required this.monthly,
    required this.duties,
    required this.assign,
  });

  factory MaterialsLinks.fromJson(Map<String, dynamic> j) => MaterialsLinks(
        history: j['history'] as String? ?? '',
        trends: j['trends'] as String? ?? '',
        monthly: j['monthly'] as String? ?? '',
        duties: j['duties'] as String? ?? '',
        assign: j['assign'] as String? ?? '',
      );

  final String history;
  final String trends;
  final String monthly;
  final String duties;
  final String assign;

  Map<String, dynamic> toJson() => {
        'history': history,
        'trends': trends,
        'monthly': monthly,
        'duties': duties,
        'assign': assign,
      };
}

/// One day's sheet, matching `api/v1/materials/today.php`.
class MaterialsDay {
  MaterialsDay({
    required this.date,
    required this.dateLabel,
    required this.uploadLimit,
    required this.isAdmin,
    required this.canMonthly,
    required this.summary,
    required this.conditions,
    required this.locations,
    required this.materials,
    required this.links,
  });

  factory MaterialsDay.fromJson(Map<String, dynamic> j) => MaterialsDay(
        date: j['date'] as String? ?? '',
        dateLabel: j['date_label'] as String? ?? '',
        uploadLimit: j['upload_limit'] as int? ?? 40 * 1024 * 1024,
        isAdmin: j['is_admin'] as bool? ?? false,
        canMonthly: j['can_monthly'] as bool? ?? false,
        summary: MaterialsSummary.fromJson((j['summary'] as Map?)?.cast<String, dynamic>() ?? const {}),
        conditions: [
          for (final c in (j['conditions'] as List? ?? const []))
            MaterialCondition.fromJson((c as Map).cast<String, dynamic>()),
        ],
        locations: [for (final l in (j['locations'] as List? ?? const [])) l as String],
        materials: [
          for (final m in (j['materials'] as List? ?? const []))
            MaterialItem.fromJson((m as Map).cast<String, dynamic>()),
        ],
        links: MaterialsLinks.fromJson((j['links'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );

  final String date;
  final String dateLabel;
  final int uploadLimit;
  final bool isAdmin;
  final bool canMonthly;
  final MaterialsSummary summary;
  final List<MaterialCondition> conditions;
  final List<String> locations;
  final List<MaterialItem> materials;
  final MaterialsLinks links;

  Map<String, dynamic> toJson() => {
        'date': date,
        'date_label': dateLabel,
        'upload_limit': uploadLimit,
        'is_admin': isAdmin,
        'can_monthly': canMonthly,
        'summary': summary.toJson(),
        'conditions': [for (final c in conditions) c.toJson()],
        'locations': locations,
        'materials': [for (final m in materials) m.toJson()],
        'links': links.toJson(),
      };
}

class MaterialsApi {
  MaterialsApi(this.api);

  final ApiClient api;

  Future<MaterialsDay> today([String? date]) async {
    final d = await api.get('materials/today.php', date == null || date.isEmpty ? null : {'date': date});
    return MaterialsDay.fromJson(d['day'] as Map<String, dynamic>);
  }

  Future<void> mark({
    required int materialId,
    required String date,
    required String conditionCode,
    required String notes,
    required String clientKey,
  }) {
    return api.post('materials/mark.php', {
      'material_id': materialId,
      'date': date,
      'condition_code': conditionCode,
      'notes': notes,
      'client_key': clientKey,
    });
  }

  Future<void> bulkGood({required String date, required String scope, required String clientKey}) {
    return api.post('materials/bulk_good.php', {
      'date': date,
      'scope': scope,
      'client_key': clientKey,
    });
  }

  Future<void> uploadFile({
    required int materialId,
    required String date,
    required String clientKey,
    required String filePath,
    required String filename,
  }) {
    return api.postMultipart(
      'materials/media.php',
      fields: {
        'material_id': '$materialId',
        'date': date,
        'client_key': clientKey,
      },
      filePath: filePath,
      filename: filename,
    );
  }
}
