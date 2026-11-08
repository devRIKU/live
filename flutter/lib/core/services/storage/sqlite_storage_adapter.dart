/// SqliteStorageAdapter — desktop implementation of `StorageAdapter`.
///
/// Port of `src/db/sqliteAdapter.ts`. The web build used IndexedDB
/// (`MemoryStorageAdapter` in Flutter); the desktop build uses a local SQLite
/// file via `sqflite_common_ffi`. Both implement the same interface, so the
/// JSON export/import format is shared between them.
///
/// The stores are separate per runtime — the JSON export/import file is the
/// only way to move data between them, exactly like the TS original.
library;

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models/models.dart';
import '../storage_adapter.dart';

class SqliteStorageAdapter implements StorageAdapter {
  SqliteStorageAdapter(this._database);

  final Database _database;
  Future<void>? _schema;

  /// Open (or create) the default desktop database in the app-support
  /// directory and return a ready adapter.
  static Future<SqliteStorageAdapter> open(
      {String fileName = 'openall.db'}) async {
    sqfliteFfiInit();
    final dir = await getApplicationSupportDirectory();
    final db = await databaseFactoryFfi.openDatabase(
      p.join(dir.path, fileName),
      options: OpenDatabaseOptions(version: 1),
    );
    return SqliteStorageAdapter(db);
  }

  /// Runs the full schema (idempotent) before the first query.
  Future<Database> _db() async {
    _schema ??= _ensureSchema(_database);
    await _schema!;
    return _database;
  }

  Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS threads (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        messages TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS facts (
        id TEXT PRIMARY KEY,
        fact TEXT NOT NULL,
        category TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> close() => _database.close();

  // ── Threads ──────────────────────────────────────────────────────────────

  @override
  Future<Thread?> getThread(String id) async {
    final db = await _db();
    final rows = await db
        .rawQuery('SELECT * FROM threads WHERE id = ?', <Object?>[id]);
    if (rows.isEmpty) return null;
    return _rowToThread(rows.first);
  }

  @override
  Future<void> saveThread(Thread thread) async {
    assertNoSecrets(thread.toJson(), 'thread');
    final db = await _db();
    await db.rawInsert(
      '''
      INSERT INTO threads (id, title, created_at, updated_at, messages)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        updated_at = excluded.updated_at,
        messages = excluded.messages
      ''',
      <Object?>[
        thread.id,
        thread.title,
        thread.createdAt,
        thread.updatedAt,
        jsonEncode(thread.messages.map((m) => m.toJson()).toList()),
      ],
    );
  }

  @override
  Future<List<ThreadSummary>> listThreads() async {
    final db = await _db();
    final rows = await db.rawQuery('SELECT * FROM threads ORDER BY updated_at DESC');
    return rows
        .map((r) => ThreadSummary(
              id: r['id']! as String,
              title: r['title']! as String,
              createdAt: (r['created_at']! as num).toInt(),
              updatedAt: (r['updated_at']! as num).toInt(),
            ))
        .toList();
  }

  @override
  Future<void> deleteThread(String id) async {
    final db = await _db();
    await db.rawDelete('DELETE FROM threads WHERE id = ?', <Object?>[id]);
  }

  // ── Settings ─────────────────────────────────────────────────────────────

  @override
  Future<T?> getSetting<T>(String key) async {
    final db = await _db();
    final rows = await db
        .rawQuery('SELECT value FROM settings WHERE key = ?', <Object?>[key]);
    if (rows.isEmpty) return null;
    final Object? decoded = jsonDecode(rows.first['value']! as String);
    // JSON objects decode to `Map<dynamic, dynamic>`; normalise for callers.
    if (decoded is Map) return Map<String, dynamic>.from(decoded) as T?;
    return decoded as T?;
  }

  @override
  Future<void> setSetting<T>(String key, T value) async {
    assertNoSecrets(<String, Object?>{'key': key, 'value': value}, 'setting');
    final db = await _db();
    await db.rawInsert(
      '''
      INSERT INTO settings (key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
      ''',
      <Object?>[key, jsonEncode(value)],
    );
  }

  // ── Facts ────────────────────────────────────────────────────────────────

  static Map<String, Object?> _factValues(Fact fact) => <String, Object?>{
        'id': fact.id,
        'fact': fact.fact,
        'category': fact.category,
        'created_at': fact.createdAt,
      };

  Fact _rowToFact(Map<String, Object?> r) => Fact(
        id: r['id']! as String,
        fact: r['fact']! as String,
        category: r['category']! as String,
        createdAt: (r['created_at']! as num).toInt(),
      );

  @override
  Future<Fact?> getFact(String id) async {
    final db = await _db();
    final rows =
        await db.rawQuery('SELECT * FROM facts WHERE id = ?', <Object?>[id]);
    if (rows.isEmpty) return null;
    return _rowToFact(rows.first);
  }

  @override
  Future<void> saveFact(Fact fact) async {
    assertNoSecrets(fact.toJson(), 'fact');
    final db = await _db();
    final v = _factValues(fact);
    await db.rawInsert(
      '''
      INSERT INTO facts (id, fact, category, created_at) VALUES (?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        fact = excluded.fact,
        category = excluded.category
      ''',
      <Object?>[v['id'], v['fact'], v['category'], v['created_at']],
    );
  }

  @override
  Future<List<Fact>> listFacts() async {
    final db = await _db();
    final rows = await db.rawQuery('SELECT * FROM facts ORDER BY created_at DESC');
    return rows.map(_rowToFact).toList();
  }

  @override
  Future<void> deleteFact(String id) async {
    final db = await _db();
    await db.rawDelete('DELETE FROM facts WHERE id = ?', <Object?>[id]);
  }

  @override
  Future<void> clearFacts() async {
    final db = await _db();
    await db.delete('facts');
  }

  // ── Export / Import ──────────────────────────────────────────────────────

  @override
  Future<ExportPayload> exportAll() async {
    final db = await _db();
    final threadRows = await db.rawQuery('SELECT * FROM threads');
    final factRows = await db.rawQuery('SELECT * FROM facts');

    return ExportPayload(
      exportedAt: DateTime.now().millisecondsSinceEpoch,
      threads: threadRows.map(_rowToThread).toList(),
      facts: factRows.map(_rowToFact).toList(),
    );
  }

  @override
  Future<ImportResult> importAll(ExportPayload data) async {

    var imported = 0;
    var skipped = 0;

    for (final thread in data.threads) {
      try {
        assertNoSecrets(thread.toJson(), 'imported thread');
        await saveThread(thread);
        imported++;
      } catch (_) {
        skipped++;
      }
    }

    for (final fact in data.facts) {
      try {
        assertNoSecrets(fact.toJson(), 'imported fact');
        await saveFact(fact);
        imported++;
      } catch (_) {
        skipped++;
      }
    }

    return ImportResult(imported: imported, skipped: skipped);
  }

  Thread _rowToThread(Map<String, Object?> row) {
    final messages = jsonDecode(row['messages']! as String) as List<Object?>;
    return Thread(
      id: row['id']! as String,
      title: row['title']! as String,
      createdAt: (row['created_at']! as num).toInt(),
      updatedAt: (row['updated_at']! as num).toInt(),
      messages: messages
          .map((m) => Message.fromJson(Map<String, dynamic>.from(m! as Map)))
          .toList(),
    );
  }
}
