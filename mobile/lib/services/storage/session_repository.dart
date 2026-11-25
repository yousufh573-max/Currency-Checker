import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/analysis_result.dart';
import '../../models/session.dart';

/// Local SQLite storage for sessions (works fully offline).
///
/// Stores only amounts and analysis results — never images or serial numbers.
/// `capture_id` is the primary key, so a repeated insert of the same capture
/// (camera repeat / retry) is ignored at the database level too.
class SessionRepository {
  SessionRepository(this._db);
  final Database _db;

  static Future<SessionRepository> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'banknote_assistant.db');
    final db = await f.openDatabase(dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            await db.execute('''CREATE TABLE sessions(
              id TEXT PRIMARY KEY, status TEXT NOT NULL, required_amount INTEGER,
              total INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, completed_at TEXT)''');
            await db.execute('''CREATE TABLE scans(
              capture_id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
              seq INTEGER NOT NULL, denomination INTEGER, confidence REAL, torn_ratio REAL, condition TEXT NOT NULL,
              accepted INTEGER NOT NULL, reason TEXT, demo INTEGER NOT NULL, created_at TEXT NOT NULL)''');
          },
        ));
    return SessionRepository(db);
  }

  Future<void> save(SessionState s) async {
    await _db.transaction((txn) async {
      await txn.insert(
          'sessions',
          {
            'id': s.id,
            'status': s.completed ? 'completed' : 'active',
            'required_amount': s.requiredAmount,
            'total': s.total,
            'created_at': (s.scans.isEmpty ? DateTime.now() : s.scans.first.createdAt).toIso8601String(),
            'completed_at': s.completed ? DateTime.now().toIso8601String() : null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      // Rewrite scans so undo is reflected.
      await txn.delete('scans', where: 'session_id = ?', whereArgs: [s.id]);
      for (var i = 0; i < s.scans.length; i++) {
        final r = s.scans[i];
        await txn.insert(
            'scans',
            {
              'capture_id': r.captureId,
              'session_id': s.id,
              'seq': i,
              'denomination': r.denomination,
              'confidence': r.confidence,
              'torn_ratio': r.tornRatio,
              'condition': r.condition.name,
              'accepted': r.accepted ? 1 : 0,
              'reason': r.reason,
              'demo': r.isDemo ? 1 : 0,
              'created_at': r.createdAt.toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<SessionState?> loadActive() async {
    final rows = await _db.query('sessions', where: 'status = ?', whereArgs: ['active'], orderBy: 'created_at DESC', limit: 1);
    if (rows.isEmpty) return null;
    return _load(rows.first);
  }

  Future<SessionState> _load(Map<String, Object?> row) async {
    final id = row['id']! as String;
    final scans = await _db.query('scans', where: 'session_id = ?', whereArgs: [id], orderBy: 'seq');
    return SessionState(
      id: id,
      requiredAmount: row['required_amount'] as int?,
      completed: row['status'] == 'completed',
      scans: [
        for (final r in scans)
          ScanRecord(
            captureId: r['capture_id']! as String,
            denomination: r['denomination'] as int?,
            confidence: r['confidence'] as double?,
            tornRatio: r['torn_ratio'] as double?,
            condition: NoteCondition.values.byName(r['condition']! as String),
            accepted: r['accepted'] == 1,
            reason: r['reason'] as String?,
            isDemo: r['demo'] == 1,
            createdAt: DateTime.parse(r['created_at']! as String),
          )
      ],
    );
  }

  Future<List<SessionState>> history({int limit = 20}) async {
    final rows = await _db.query('sessions', where: 'status = ?', whereArgs: ['completed'], orderBy: 'completed_at DESC', limit: limit);
    return [for (final r in rows) await _load(r)];
  }

  Future<void> delete(String id) => _db.delete('sessions', where: 'id = ?', whereArgs: [id]);

  Future<void> close() => _db.close();
}
