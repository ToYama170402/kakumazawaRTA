import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoge/measurement/position.dart';
import 'package:hoge/runs/pending_run_queue.dart';
import 'package:hoge/runs/run_submission_request.dart';
import 'package:hoge/runs/secure_run_submitter.dart';
import 'package:hoge/runs/submit_run_http_uploader.dart';
import 'package:hoge/security/encrypted_run_storage.dart';
import 'package:hoge/security/run_key_manager.dart';
import 'package:hoge/security/secure_run_session_manager.dart';

void main() {
  test(
    'submit decrypts, uploads and removes local encrypted data + key',
    () async {
      final keyManager = InMemoryRunKeyManager();
      final storage = MemoryEncryptedRunStorage();
      final sessionManager = SecureRunSessionManager(
        keyManager: keyManager,
        storage: storage,
      );

      final runId = await sessionManager.startRun();
      await sessionManager.stopRunAndStoreEncrypted(<GeoPoint>[
        GeoPoint(
          latitude: 36.54,
          longitude: 136.70,
          timestamp: DateTime.utc(2026, 6, 30, 0, 0, 0),
        ),
        GeoPoint(
          latitude: 36.55,
          longitude: 136.71,
          timestamp: DateTime.utc(2026, 6, 30, 0, 0, 1),
        ),
      ]);

      final uploader = InMemoryRunUploader();
      final queue = MemoryPendingRunQueue();
      final submitter = SecureRunSubmitter(
        secureRunSessionManager: sessionManager,
        uploader: uploader,
        requestFactory: const DemoRunSubmissionRequestFactory(),
        pendingRunQueue: queue,
      );

      await submitter.submit(runId);

      expect(uploader.uploadedRuns.containsKey(runId), isTrue);
      expect(uploader.uploadedRuns[runId]!.locationHistory.length, 2);

      final stored = await storage.readByRunId(runId);
      expect(stored, isNull);

      expect(() => keyManager.getForRun(runId), throwsStateError);
      expect(await queue.readByRunId(runId), isNull);
    },
  );

  group('retry on upload failure', () {
    test('queues run on HTTP upload failure with retryCount=0', () async {
      final keyManager = InMemoryRunKeyManager();
      final storage = MemoryEncryptedRunStorage();
      final sessionManager = SecureRunSessionManager(
        keyManager: keyManager,
        storage: storage,
      );

      final runId = await sessionManager.startRun();
      await sessionManager.stopRunAndStoreEncrypted(<GeoPoint>[
        GeoPoint(
          latitude: 36.54,
          longitude: 136.70,
          timestamp: DateTime.utc(2026, 6, 30, 0, 0, 0),
        ),
      ]);

      final uploader = FailingRunUploader();
      final queue = MemoryPendingRunQueue();
      final submitter = SecureRunSubmitter(
        secureRunSessionManager: sessionManager,
        uploader: uploader,
        requestFactory: const DemoRunSubmissionRequestFactory(),
        pendingRunQueue: queue,
      );

      // First submit attempt fails
      await expectLater(
        () => submitter.submit(runId),
        throwsA(isA<HttpException>()),
      );

      // Record should be in queue
      final record = await queue.readByRunId(runId);
      expect(record, isNotNull);
      expect(record!.retryCount, 0);
      expect(record.runId, runId);
    });

    test('increments retryCount on subsequent failures', () async {
      final keyManager = InMemoryRunKeyManager();
      final storage = MemoryEncryptedRunStorage();
      final sessionManager = SecureRunSessionManager(
        keyManager: keyManager,
        storage: storage,
      );

      final runId = await sessionManager.startRun();
      await sessionManager.stopRunAndStoreEncrypted(<GeoPoint>[
        GeoPoint(
          latitude: 36.54,
          longitude: 136.70,
          timestamp: DateTime.utc(2026, 6, 30, 0, 0, 0),
        ),
      ]);

      final uploader = FailingRunUploader();
      final queue = MemoryPendingRunQueue();
      final submitter = SecureRunSubmitter(
        secureRunSessionManager: sessionManager,
        uploader: uploader,
        requestFactory: const DemoRunSubmissionRequestFactory(),
        pendingRunQueue: queue,
      );

      // First failure: retryCount=0
      await expectLater(
        () => submitter.submit(runId),
        throwsA(isA<HttpException>()),
      );

      var record = await queue.readByRunId(runId);
      expect(record!.retryCount, 0);

      // Simulate time passing and second attempt
      // Update nextAttemptAt to allow retry
      final now = DateTime.now().toUtc();
      final updatedRecord = PendingRunRecord(
        runId: record.runId,
        requestPayload: record.requestPayload,
        retryCount: 0,
        nextAttemptAt: now.subtract(Duration(minutes: 1)),
        isArchived: record.isArchived,
      );
      await queue.enqueue(updatedRecord);

      // Second failure: retryCount should be incremented to 1
      await expectLater(
        () => submitter.submit(runId),
        throwsA(isA<HttpException>()),
      );

      record = await queue.readByRunId(runId);
      expect(record!.retryCount, 1);

      final timeDiff = record.nextAttemptAt
          .difference(DateTime.now().toUtc())
          .inMinutes;

      // Verify nextAttemptAt was updated
      // Should be roughly 5 minutes from now (allow 1-2 min tolerance for test execution)
      // Verify nextAttemptAt was updated
      // Should be roughly 15 minutes from now (allow 1-2 min tolerance for test execution)
      expect(timeDiff, greaterThanOrEqualTo(4));
      expect(timeDiff, lessThanOrEqualTo(6));
    });

    test('archives run after 3 retries', () async {
      final keyManager = InMemoryRunKeyManager();
      final storage = MemoryEncryptedRunStorage();
      final sessionManager = SecureRunSessionManager(
        keyManager: keyManager,
        storage: storage,
      );

      final runId = await sessionManager.startRun();
      await sessionManager.stopRunAndStoreEncrypted(<GeoPoint>[
        GeoPoint(
          latitude: 36.54,
          longitude: 136.70,
          timestamp: DateTime.utc(2026, 6, 30, 0, 0, 0),
        ),
      ]);

      final uploader = FailingRunUploader();
      final queue = MemoryPendingRunQueue();
      final submitter = SecureRunSubmitter(
        secureRunSessionManager: sessionManager,
        uploader: uploader,
        requestFactory: const DemoRunSubmissionRequestFactory(),
        pendingRunQueue: queue,
      );

      // Set up initial record with retryCount=2 (already failed twice)
      await queue.enqueue(
        PendingRunRecord(
          runId: runId,
          requestPayload: '{"run_id":"$runId"}',
          retryCount: 2,
          nextAttemptAt: DateTime.now().toUtc().subtract(Duration(minutes: 1)),
          isArchived: false,
        ),
      );

      // Final failure attempt: should archive without incrementing (would be 3rd attempt)
      await expectLater(
        () => submitter.submit(runId),
        throwsA(isA<HttpException>()),
      );

      final record = await queue.readByRunId(runId);
      expect(record, isNotNull);
      expect(record!.isArchived, true);
      expect(
        record.retryCount,
        2,
        reason:
            'retryCount should remain 2 when archived (3 total attempts = retries 0,1,2)',
      );
    });
  });

  group('decryption failure handling', () {
    test('queues run on decryption failure', () async {
      final keyManager = InMemoryRunKeyManager();
      final storage = MemoryEncryptedRunStorage();
      final sessionManager = SecureRunSessionManager(
        keyManager: keyManager,
        storage: storage,
      );

      final runId = 'non-existent-run-id';

      final uploader = InMemoryRunUploader();
      final queue = MemoryPendingRunQueue();
      final submitter = SecureRunSubmitter(
        secureRunSessionManager: sessionManager,
        uploader: uploader,
        requestFactory: const DemoRunSubmissionRequestFactory(),
        pendingRunQueue: queue,
      );

      // Attempt to submit non-existent run
      await expectLater(
        () => submitter.submit(runId),
        throwsA(isA<StateError>()),
      );

      // Record should be queued with empty payload
      final record = await queue.readByRunId(runId);
      expect(record, isNotNull);
      expect(record!.retryCount, 0);
      expect(record.requestPayload, '');
    });
  });

  group('retryDueRuns', () {
    test('retries all due runs on app startup', () async {
      final keyManager = InMemoryRunKeyManager();
      final storage = MemoryEncryptedRunStorage();
      final sessionManager = SecureRunSessionManager(
        keyManager: keyManager,
        storage: storage,
      );

      final runId = await sessionManager.startRun();
      await sessionManager.stopRunAndStoreEncrypted(<GeoPoint>[
        GeoPoint(
          latitude: 36.54,
          longitude: 136.70,
          timestamp: DateTime.utc(2026, 6, 30, 0, 0, 0),
        ),
      ]);

      final uploader = InMemoryRunUploader();
      final queue = MemoryPendingRunQueue();

      // Pre-populate queue with a due run
      await queue.enqueue(
        PendingRunRecord(
          runId: runId,
          requestPayload: '{"run_id":"$runId"}',
          retryCount: 1,
          nextAttemptAt: DateTime.utc(2026, 6, 30, 0, 0, 0),
          isArchived: false,
        ),
      );

      final submitter = SecureRunSubmitter(
        secureRunSessionManager: sessionManager,
        uploader: uploader,
        requestFactory: const DemoRunSubmissionRequestFactory(),
        pendingRunQueue: queue,
      );

      // Retry due runs
      await submitter.retryDueRuns();

      // Run should have been removed from queue (successful upload)
      expect(await queue.readByRunId(runId), isNull);
      expect(uploader.uploadedRuns.containsKey(runId), isTrue);
    });

    test('continues retrying even if one run fails', () async {
      final keyManager = InMemoryRunKeyManager();
      final storage = MemoryEncryptedRunStorage();
      final sessionManager = SecureRunSessionManager(
        keyManager: keyManager,
        storage: storage,
      );

      final run1Id = await sessionManager.startRun();
      await sessionManager.stopRunAndStoreEncrypted(<GeoPoint>[
        GeoPoint(
          latitude: 36.54,
          longitude: 136.70,
          timestamp: DateTime.utc(2026, 6, 30, 0, 0, 0),
        ),
      ]);

      final run2Id = 'non-existent-run-id';

      final uploader = InMemoryRunUploader();
      final queue = MemoryPendingRunQueue();

      // Populate queue with one good run and one bad run
      await queue.enqueue(
        PendingRunRecord(
          runId: run1Id,
          requestPayload: '{"run_id":"$run1Id"}',
          retryCount: 1,
          nextAttemptAt: DateTime.utc(2026, 6, 30, 0, 0, 0),
          isArchived: false,
        ),
      );

      await queue.enqueue(
        PendingRunRecord(
          runId: run2Id,
          requestPayload: '{"run_id":"$run2Id"}',
          retryCount: 1,
          nextAttemptAt: DateTime.utc(2026, 6, 30, 0, 0, 0),
          isArchived: false,
        ),
      );

      final submitter = SecureRunSubmitter(
        secureRunSessionManager: sessionManager,
        uploader: uploader,
        requestFactory: const DemoRunSubmissionRequestFactory(),
        pendingRunQueue: queue,
      );

      // Retry due runs (run2 should fail, but run1 should still succeed)
      await submitter.retryDueRuns();

      // run1 should be uploaded successfully
      expect(uploader.uploadedRuns.containsKey(run1Id), isTrue);

      // run2 should still be in queue (failed)
      final run2Record = await queue.readByRunId(run2Id);
      expect(run2Record, isNotNull);
    });
  });
}

/// A test uploader that always fails with HttpException.
class FailingRunUploader implements SubmitRunUploader {
  @override
  Future<void> upload(RunSubmissionRequest request) async {
    throw HttpException('Simulated upload failure');
  }
}
