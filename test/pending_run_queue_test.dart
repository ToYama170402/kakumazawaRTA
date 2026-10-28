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

  group('updateRetryCountAndSchedule', () {
    test('increments retry count and schedules next attempt', () async {
      final queue = MemoryPendingRunQueue();
      final now = DateTime.utc(2026, 6, 30, 10, 0, 0);

      await queue.enqueue(
        PendingRunRecord(
          runId: 'run-1',
          requestPayload: '{"run_id":"run-1"}',
          retryCount: 0,
          nextAttemptAt: now,
        ),
      );

      await queue.updateRetryCountAndSchedule('run-1');

      final updated = await queue.readByRunId('run-1');
      expect(updated, isNotNull);
      expect(updated!.retryCount, 1);
      // Next attempt should be scheduled for 15 minutes later
      expect(
        updated.nextAttemptAt.difference(now).inMinutes,
        greaterThanOrEqualTo(15),
      );
    });

    test('returns without error if record does not exist', () async {
      final queue = MemoryPendingRunQueue();
      // Should not throw
      await queue.updateRetryCountAndSchedule('non-existent');
      expect(await queue.readByRunId('non-existent'), isNull);
    });
  });

  group('shouldRetry', () {
    test('returns true when retry count < 3 and time has passed', () async {
      final queue = MemoryPendingRunQueue();
      final now = DateTime.utc(2026, 6, 30, 10, 0, 0);

      await queue.enqueue(
        PendingRunRecord(
          runId: 'run-1',
          requestPayload: '{"run_id":"run-1"}',
          retryCount: 1,
          nextAttemptAt: now.subtract(Duration(minutes: 1)),
        ),
      );

      final shouldRetry = await queue.shouldRetry('run-1', now: now);
      expect(shouldRetry, true);
    });

    test('returns false when retry count >= 3', () async {
      final queue = MemoryPendingRunQueue();
      final now = DateTime.utc(2026, 6, 30, 10, 0, 0);

      await queue.enqueue(
        PendingRunRecord(
          runId: 'run-1',
          requestPayload: '{"run_id":"run-1"}',
          retryCount: 3,
          nextAttemptAt: now.subtract(Duration(minutes: 1)),
        ),
      );

      final shouldRetry = await queue.shouldRetry('run-1', now: now);
      expect(shouldRetry, false);
    });

    test('returns false when next attempt time has not passed', () async {
      final queue = MemoryPendingRunQueue();
      final now = DateTime.utc(2026, 6, 30, 10, 0, 0);

      await queue.enqueue(
        PendingRunRecord(
          runId: 'run-1',
          requestPayload: '{"run_id":"run-1"}',
          retryCount: 1,
          nextAttemptAt: now.add(Duration(minutes: 5)),
        ),
      );

      final shouldRetry = await queue.shouldRetry('run-1', now: now);
      expect(shouldRetry, false);
    });

    test('returns false when record does not exist', () async {
      final queue = MemoryPendingRunQueue();
      final shouldRetry = await queue.shouldRetry('non-existent');
      expect(shouldRetry, false);
    });
  });

  group('markAsArchived', () {
    test('sets isArchived flag to true', () async {
      final queue = MemoryPendingRunQueue();

      await queue.enqueue(
        PendingRunRecord(
          runId: 'run-1',
          requestPayload: '{"run_id":"run-1"}',
          retryCount: 3,
          nextAttemptAt: DateTime.utc(2026, 6, 30, 10, 0, 0),
        ),
      );

      await queue.markAsArchived('run-1');

      final archived = await queue.readByRunId('run-1');
      expect(archived, isNotNull);
      expect(archived!.isArchived, true);
      expect(archived.retryCount, 3);
    });

    test('returns without error if record does not exist', () async {
      final queue = MemoryPendingRunQueue();
      // Should not throw
      await queue.markAsArchived('non-existent');
      expect(await queue.readByRunId('non-existent'), isNull);
    });
  });

  group('retry count state transitions', () {
    test('progresses through retry counts 0 -> 1 -> 2 -> archived', () async {
      final queue = MemoryPendingRunQueue();
      final baseTime = DateTime.utc(2026, 6, 30, 10, 0, 0);

      // Initial enqueue with retryCount=0
      await queue.enqueue(
        PendingRunRecord(
          runId: 'run-1',
          requestPayload: '{"run_id":"run-1"}',
          retryCount: 0,
          nextAttemptAt: baseTime,
        ),
      );

      var record = await queue.readByRunId('run-1');
      expect(record!.retryCount, 0);
      expect(record.isArchived, false);

      // First retry update (0 -> 1)
      await queue.updateRetryCountAndSchedule('run-1');
      record = await queue.readByRunId('run-1');
      expect(record!.retryCount, 1);

      // Second retry update (1 -> 2)
      await queue.updateRetryCountAndSchedule('run-1');
      record = await queue.readByRunId('run-1');
      expect(record!.retryCount, 2);

      // Cannot call updateRetryCountAndSchedule for retryCount=2->3
      // (would exceed max retries). Instead, archive directly.
      await queue.markAsArchived('run-1');
      record = await queue.readByRunId('run-1');
      expect(record!.isArchived, true);
      expect(record.retryCount, 2);
    });

    test('calculates correct backoff durations during updates', () async {
      final queue = MemoryPendingRunQueue();
      final baseTime = DateTime.utc(2026, 6, 30, 10, 0, 0);

      // Start with retryCount=0
      await queue.enqueue(
        PendingRunRecord(
          runId: 'run-1',
          requestPayload: '{"run_id":"run-1"}',
          retryCount: 0,
          nextAttemptAt: baseTime,
        ),
      );

      // After first update, retryCount=0->1
      // calculateRetryBackoff(newRetryCount=1) = 5 minutes
      await queue.updateRetryCountAndSchedule('run-1');
      var record = await queue.readByRunId('run-1');
      expect(record!.retryCount, 1);
      final timeDiff1 = record.nextAttemptAt.difference(DateTime.now().toUtc());
      expect(timeDiff1.inMinutes, greaterThanOrEqualTo(4));
      expect(timeDiff1.inMinutes, lessThanOrEqualTo(6));

      // After second update, retryCount=1->2
      // calculateRetryBackoff(newRetryCount=2) = 15 minutes
      await queue.updateRetryCountAndSchedule('run-1');
      record = await queue.readByRunId('run-1');
      expect(record!.retryCount, 2);
      final timeDiff2 = record.nextAttemptAt.difference(DateTime.now().toUtc());
      expect(timeDiff2.inMinutes, greaterThanOrEqualTo(14));
      expect(timeDiff2.inMinutes, lessThanOrEqualTo(16));
    });
  });
}
