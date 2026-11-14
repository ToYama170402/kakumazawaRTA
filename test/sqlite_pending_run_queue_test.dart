import 'package:flutter_test/flutter_test.dart';
import 'package:hoge/runs/pending_run_queue.dart';
import 'package:hoge/runs/pending_runs_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<SqlitePendingRunQueue> openQueue() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: createPendingRunsDatabase,
      ),
    );
    return SqlitePendingRunQueue(databaseProvider: () async => db);
  }

  PendingRunRecord record({
    required String runId,
    int retryCount = 0,
    DateTime? nextAttemptAt,
    bool isArchived = false,
  }) {
    return PendingRunRecord(
      runId: runId,
      requestPayload: '{"run_id":"$runId","ciphertext_b64":"xyz"}',
      retryCount: retryCount,
      nextAttemptAt: nextAttemptAt ?? DateTime.utc(2026, 6, 30),
      isArchived: isArchived,
    );
  }

  test('enqueue / read / delete が SQLite で往復する', () async {
    final queue = await openQueue();

    await queue.enqueue(record(runId: 'run-1'));
    final stored = await queue.readByRunId('run-1');
    expect(stored, isNotNull);
    expect(stored!.retryCount, 0);
    expect(stored.requestPayload, contains('ciphertext_b64'));
    expect(stored.isArchived, isFalse);

    await queue.deleteByRunId('run-1');
    expect(await queue.readByRunId('run-1'), isNull);
  });

  test('dueRuns は期限到来分だけを返す', () async {
    final queue = await openQueue();
    final now = DateTime.utc(2026, 7, 1, 12);

    await queue.enqueue(
      record(
        runId: 'due',
        nextAttemptAt: now.subtract(const Duration(minutes: 1)),
      ),
    );
    await queue.enqueue(
      record(
        runId: 'not-due',
        nextAttemptAt: now.add(const Duration(hours: 1)),
      ),
    );

    final due = await queue.dueRuns(now: now);
    expect(due.map((r) => r.runId), ['due']);
  });

  test('updateRetryCountAndSchedule は回数を増やし次回時刻を後ろ倒す', () async {
    final queue = await openQueue();
    await queue.enqueue(record(runId: 'run-1'));

    await queue.updateRetryCountAndSchedule('run-1');
    final updated = await queue.readByRunId('run-1');
    expect(updated!.retryCount, 1);
    expect(updated.nextAttemptAt.isAfter(DateTime.now().toUtc()), isTrue);

    // 存在しない runId でも例外にならない
    await queue.updateRetryCountAndSchedule('missing');
  });

  test('shouldRetry と markAsArchived が状態遷移する', () async {
    final queue = await openQueue();
    final past = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    await queue.enqueue(record(runId: 'run-1', nextAttemptAt: past));

    expect(await queue.shouldRetry('run-1'), isTrue);

    await queue.markAsArchived('run-1');
    final archived = await queue.readByRunId('run-1');
    expect(archived!.isArchived, isTrue);

    await queue.enqueue(
      record(runId: 'run-max', retryCount: 3, nextAttemptAt: past),
    );
    expect(await queue.shouldRetry('run-max'), isFalse);
    expect(await queue.shouldRetry('missing'), isFalse);
  });

  test('スキーマに pending_runs テーブルが定義されている', () {
    expect(pendingRunsCreateTableSql, contains('pending_runs'));
    expect(pendingRunsCreateTableSql, contains('run_id TEXT PRIMARY KEY'));
    expect(pendingRunsCreateTableSql, contains('request_payload'));
    expect(pendingRunsCreateTableSql, contains('retry_count'));
    expect(pendingRunsCreateTableSql, contains('next_attempt_at'));
    expect(pendingRunsCreateTableSql, contains('is_archived'));
  });
}
