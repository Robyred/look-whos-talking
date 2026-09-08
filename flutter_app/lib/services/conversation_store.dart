import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/conversation_record.dart';

/// Local persistence layer (SQLite) — one row per completed diarization job.
///
/// Accepts an injectable [DatabaseFactory] so tests can run against
/// sqflite_common_ffi on the host instead of a device.
class ConversationStore {
  ConversationStore({DatabaseFactory? factory, this.dbPath})
      : _factory = factory ?? databaseFactory;

  static const _dbFileName = 'conversations.db';
  static const _schemaVersion = 1;

  final DatabaseFactory _factory;
  final String? dbPath;

  Database? _db;
  Future<Database>? _opening;

  Future<Database> _database() {
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    final path =
        dbPath ?? p.join(await _factory.getDatabasesPath(), _dbFileName);
    return _db = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE conversations (
              id TEXT PRIMARY KEY,
              filename TEXT NOT NULL,
              created_at TEXT NOT NULL,
              duration_sec REAL NOT NULL,
              speaker_count INTEGER NOT NULL,
              result_json TEXT NOT NULL,
              audio_path TEXT,
              is_synced INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE metadata (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
          await db.insert('metadata', {'key': 'schema_version', 'value': '1'});
        },
      ),
    );
  }

  // Inserts or replaces — re-saving the same id overwrites (idempotent).
  Future<void> save(ConversationRecord record) async {
    final db = await _database();
    await db.insert(
      'conversations',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // All records, newest first.
  Future<List<ConversationRecord>> list() async {
    final db = await _database();
    final rows = await db.query('conversations', orderBy: 'created_at DESC');
    return rows.map(ConversationRecord.fromMap).toList();
  }

  Future<ConversationRecord?> get(String id) async {
    final db = await _database();
    final rows =
        await db.query('conversations', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ConversationRecord.fromMap(rows.first);
  }

  // Deletes the audio file from disk (if present) and nulls audio_path.
  // Never throws when the file is already gone from disk.
  Future<void> deleteAudio(String id) async {
    final db = await _database();
    final rows =
        await db.query('conversations', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;

    final audioPath = rows.first['audio_path'] as String?;
    if (audioPath == null) return;

    await _deleteFileIfPresent(File(audioPath));
    await db.update(
      'conversations',
      {'audio_path': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Removes the DB record and deletes its audio file (if present).
  Future<void> delete(String id) async {
    final db = await _database();
    final rows =
        await db.query('conversations', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;

    final audioPath = rows.first['audio_path'] as String?;
    await db.delete('conversations', where: 'id = ?', whereArgs: [id]);

    if (audioPath != null) {
      await _deleteFileIfPresent(File(audioPath));
    }
  }

  Future<void> markSynced(String id) async {
    final db = await _database();
    await db.update(
      'conversations',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() async {
    final db = _db;
    _opening = null;
    _db = null;
    await db?.close();
  }

  /// Test seam: the live database handle, so tests can assert it was closed.
  @visibleForTesting
  Database? get debugDatabase => _db;

  Future<void> _deleteFileIfPresent(File file) async {
    if (!await file.exists()) return;
    try {
      await file.delete();
    } on FileSystemException {
      // Lost a race (deleted between exists() and delete()) — treat as gone.
      if (await file.exists()) rethrow;
    }
  }
}
