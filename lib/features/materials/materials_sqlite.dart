import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'materials_queue.dart';

class SqliteMaterialsStore implements MaterialsStore {
  SqliteMaterialsStore(this._db);

  final Database _db;

  Future<void> close() => _db.close();

  static Future<SqliteMaterialsStore> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), 'materials_outbox.db');
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_key TEXT NOT NULL UNIQUE,
            kind TEXT NOT NULL,
            check_date TEXT NOT NULL,
            material_id INTEGER,
            location TEXT NOT NULL DEFAULT '',
            scope TEXT NOT NULL DEFAULT '',
            condition_code TEXT,
            notes TEXT NOT NULL DEFAULT '',
            original_path TEXT,
            upload_path TEXT,
            media_kind TEXT NOT NULL DEFAULT '',
            filename TEXT NOT NULL DEFAULT '',
            mime TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            generation INTEGER NOT NULL DEFAULT 1,
            sent_generation INTEGER,
            error_code TEXT,
            last_error TEXT,
            upload_channel TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT NOT NULL)');
      },
    );
    return SqliteMaterialsStore(db);
  }

  @override
  Future<List<OutboxItem>> all() async {
    final rows = await _db.query('outbox', orderBy: 'id');
    return [for (final row in rows) _from(row)];
  }

  @override
  Future<OutboxItem?> get(int id) async {
    final rows = await _db.query('outbox', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _from(rows.first);
  }

  @override
  Future<OutboxItem> insert(OutboxItem item) async {
    final values = _to(item)..remove('id');
    final id = await _db.insert('outbox', values);
    return item.copyWith(id: id);
  }

  @override
  Future<void> update(OutboxItem item) async {
    final values = _to(item)..remove('id');
    await _db.update('outbox', values, where: 'id = ?', whereArgs: [item.id]);
  }

  @override
  Future<bool> claim(int id, {required OutboxStatus from, required OutboxStatus to, required DateTime updatedAt}) async {
    final n = await _db.update(
      'outbox',
      {'status': to.name, 'updated_at': updatedAt.toIso8601String()},
      where: 'id = ? AND status = ?',
      whereArgs: [id, from.name],
    );
    return n == 1;
  }

  @override
  Future<void> setMeta(String key, String value) async {
    await _db.insert('meta', {'k': key, 'v': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<String?> getMeta(String key) async {
    final rows = await _db.query('meta', where: 'k = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['v'] as String?;
  }

  @override
  Future<void> requeueAuthFailures(DateTime updatedAt) async {
    await _db.update(
      'outbox',
      {
        'status': OutboxStatus.pending.name,
        'attempts': 0,
        'error_code': null,
        'last_error': null,
        'updated_at': updatedAt.toIso8601String(),
      },
      where: 'status = ? AND error_code = ?',
      whereArgs: [OutboxStatus.failed.name, 'auth'],
    );
  }

  @override
  Future<void> purgeUploaded() async {
    await _db.delete('outbox', where: 'status = ?', whereArgs: [OutboxStatus.uploaded.name]);
  }

  Map<String, Object?> _to(OutboxItem item) => {
        'id': item.id,
        'client_key': item.clientKey,
        'kind': item.kind.name,
        'check_date': item.checkDate,
        'material_id': item.materialId,
        'location': item.location,
        'scope': item.scope,
        'condition_code': item.conditionCode,
        'notes': item.notes,
        'original_path': item.originalPath,
        'upload_path': item.uploadPath,
        'media_kind': item.mediaKind,
        'filename': item.filename,
        'mime': item.mime,
        'status': item.status.name,
        'attempts': item.attempts,
        'generation': item.generation,
        'sent_generation': item.sentGeneration,
        'error_code': item.errorCode,
        'last_error': item.lastError,
        'upload_channel': item.uploadChannel,
        'created_at': item.createdAt.toIso8601String(),
        'updated_at': item.updatedAt.toIso8601String(),
      };

  OutboxItem _from(Map<String, Object?> row) => OutboxItem(
        id: row['id'] as int?,
        clientKey: row['client_key'] as String,
        kind: OutboxKind.values.byName(row['kind'] as String),
        checkDate: row['check_date'] as String,
        materialId: row['material_id'] as int?,
        location: row['location'] as String? ?? '',
        scope: row['scope'] as String? ?? '',
        conditionCode: row['condition_code'] as String?,
        notes: row['notes'] as String? ?? '',
        originalPath: row['original_path'] as String?,
        uploadPath: row['upload_path'] as String?,
        mediaKind: row['media_kind'] as String? ?? '',
        filename: row['filename'] as String? ?? '',
        mime: row['mime'] as String? ?? '',
        status: OutboxStatus.values.byName(row['status'] as String),
        attempts: row['attempts'] as int? ?? 0,
        generation: row['generation'] as int? ?? 1,
        sentGeneration: row['sent_generation'] as int?,
        errorCode: row['error_code'] as String?,
        lastError: row['last_error'] as String?,
        uploadChannel: row['upload_channel'] as String? ?? '',
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );
}
