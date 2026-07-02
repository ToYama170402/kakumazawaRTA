import 'package:flutter_test/flutter_test.dart';

import 'package:hoge/runs/pending_run_queue.dart';

void main() {
  test('pending run queue stores and returns due runs', () async {
    final queue = MemoryPendingRunQueue();

    await queue.enqueue(
      PendingRunRecord(
        runId: 'run-1',
        requestPayload: '{"run_id":"run-1"}',
        retryCount: 1,
        nextAttemptAt: DateTime.utc(2026, 6, 30, 0, 0, 0),
      ),
    );

    final due = await queue.dueRuns(now: DateTime.utc(2026, 6, 30, 0, 0, 1));
    expect(due.single.runId, 'run-1');
    expect(await queue.readByRunId('run-1'), isNotNull);

    await queue.deleteByRunId('run-1');
    expect(await queue.readByRunId('run-1'), isNull);
  });
}
