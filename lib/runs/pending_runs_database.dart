import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'pending_run_queue.dart';
import 'retry_schedule.dart';

/// `pending_runs` テーブルのスキーマ（Issue #25）。
///
/// 詳細設計 3.1 に基づく。`run_id` を主キーとし、アプリ再起動を跨いでも
/// 再送待ちの走行を保持できるよう SQLite に保存する。
const String pendingRunsCreateTableSql = '''
CREATE TABLE IF NOT EXISTS pending_runs (
  run_id TEXT PRIMARY KEY,
  request_payload TEXT NOT NULL,
  retry_count INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TEXT NOT NULL,
  is_archived INTEGER NOT NULL DEFAULT 0
)
''';

/// onCreate 用コールバック。マイグレーション追加時はここを起点にする。
Future<void> createPendingRunsDatabase(Database db, int version) async {
  await db.execute(pendingRunsCreateTableSql);
}

/// SQLite 版の [PendingRunQueue]（Issue #3, #25, #26）。
///
/// 既存の [FilePendingRunQueue] と同じ意味論を持ち、保存先だけが違う。
/// 本番では端末のデータベース領域に開き、テストでは
/// [databaseProvider] にインメモリDB等を差し替えられる。
class SqlitePendingRunQueue implements PendingRunQueue {
  SqlitePendingRunQueue({Future<Database> Function()? databaseProvider})
    : _databaseProvider = databaseProvider ?? _openProductionDatabase;

  final Future<Database> Function() _databaseProvider;

  Database? _database;

  static Future<Database> _openProductionDatabase() async {
    final directory = await getDatabasesPath();
    return openDatabase(
      p.join(directory, 'kakumazawa_rta.db'),
      version: 1,
      onCreate: createPendingRunsDatabase,
    );
  }

  Future<Database> _db() async {
    return _database ??= await _databaseProvider();
  }

  @override
  Future<void> enqueue(PendingRunRecord record) async {
    final db = await _db();
    await db.insert(
      'pending_runs',
      _toRow(record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<PendingRunRecord>> dueRuns({DateTime? now}) async {
    final db = await _db();
    final current = (now ?? DateTime.now().toUtc()).toUtc();
    final rows = await db.query(
      'pending_runs',
      where: 'next_attempt_at <= ?',
      whereArgs: [current.toIso8601String()],
      orderBy: 'next_attempt_at ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<PendingRunRecord?> readByRunId(String runId) async {
    final db = await _db();
    final rows = await db.query(
      'pending_runs',
      where: 'run_id = ?',
      whereArgs: [runId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _fromRow(rows.first);
  }

  @override
  Future<void> deleteByRunId(String runId) async {
    final db = await _db();
    await db.delete('pending_runs', where: 'run_id = ?', whereArgs: [runId]);
  }

  @override
  Future<void> updateRetryCountAndSchedule(String runId) async {
    final record = await readByRunId(runId);
    if (record == null) {
      return;
    }

    // バックオフは増やす前の retry_count で決める
    // （0→5分、1→15分、2→1時間）。FilePendingRunQueue と同じ意味論。
    final backoff = calculateRetryBackoff(record.retryCount);
    final updated = PendingRunRecord(
      runId: record.runId,
      requestPayload: record.requestPayload,
      retryCount: record.retryCount + 1,
      nextAttemptAt: DateTime.now().toUtc().add(backoff),
      isArchived: record.isArchived,
    );

    final db = await _db();
    await db.update(
      'pending_runs',
      _toRow(updated),
      where: 'run_id = ?',
      whereArgs: [runId],
    );
  }

  @override
  Future<bool> shouldRetry(String runId, {DateTime? now}) async {
    final record = await readByRunId(runId);
    if (record == null) {
      return false;
    }
    if (record.retryCount >= 3) {
      return false;
    }
    final current = (now ?? DateTime.now().toUtc()).toUtc();
    return !record.nextAttemptAt.isAfter(current);
  }

  @override
  Future<void> markAsArchived(String runId) async {
    final db = await _db();
    await db.update(
      'pending_runs',
      <String, Object?>{'is_archived': 1},
      where: 'run_id = ?',
      whereArgs: [runId],
    );
  }

  Map<String, Object?> _toRow(PendingRunRecord record) {
    return <String, Object?>{
      'run_id': record.runId,
      'request_payload': record.requestPayload,
      'retry_count': record.retryCount,
      'next_attempt_at': record.nextAttemptAt.toUtc().toIso8601String(),
      'is_archived': record.isArchived ? 1 : 0,
    };
  }

  PendingRunRecord _fromRow(Map<String, Object?> row) {
    return PendingRunRecord(
      runId: row['run_id'] as String,
      requestPayload: row['request_payload'] as String,
      retryCount: (row['retry_count'] as num).toInt(),
      nextAttemptAt: DateTime.parse(
        row['next_attempt_at'] as String,
      ).toUtc(),
      isArchived: (row['is_archived'] as num).toInt() != 0,
    );
  }
}
