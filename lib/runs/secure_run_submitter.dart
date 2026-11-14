import 'dart:convert';

import 'pending_run_queue.dart';
import 'run_submission_request.dart';
import 'submit_run_http_uploader.dart';
import '../security/secure_run_session_manager.dart';

class SecureRunSubmitter {
  /// 再送キューの request_payload には、平文のリクエストではなく
  /// 暗号化済みレコードの JSON を保存する（Issue #28）。
  /// 再送時は runId から復号し直すため、payload 自体は監査・整合確認用。

  SecureRunSubmitter({
    required SecureRunSessionManager secureRunSessionManager,
    required SubmitRunUploader uploader,
    required RunSubmissionRequestFactory requestFactory,
    PendingRunQueue? pendingRunQueue,
  }) : _secureRunSessionManager = secureRunSessionManager,
       _uploader = uploader,
       _requestFactory = requestFactory,
       _pendingRunQueue = pendingRunQueue ?? MemoryPendingRunQueue();

  final SecureRunSessionManager _secureRunSessionManager;
  final SubmitRunUploader _uploader;
  final RunSubmissionRequestFactory _requestFactory;
  final PendingRunQueue _pendingRunQueue;

  /// Submits a run to the server.
  ///
  /// If the submission fails due to network errors or other HTTP issues,
  /// the run is queued for retry with exponential backoff (5 min, 15 min, 1 hour).
  ///
  /// If the decryption fails (StateError), the run is also queued for retry.
  ///
  /// After 3 retry attempts, the run is archived and will only be retried
  /// once more on app startup.
  Future<void> submit(String runId) async {
    RunSubmissionRequest request;

    try {
      final history = await _secureRunSessionManager.decryptForSend(runId);
      request = _requestFactory.create(runId: runId, locationHistory: history);
    } on StateError {
      // Decryption failed: queue for retry
      final existingRecord = await _pendingRunQueue.readByRunId(runId);
      final retryCount = existingRecord?.retryCount ?? 0;

      if (retryCount >= 3) {
        // Already exceeded max retries, archive it
        await _pendingRunQueue.markAsArchived(runId);
      } else {
        // Queue for retry with the encrypted payload (Issue #28)
        final payloadRecord = PendingRunRecord(
          runId: runId,
          requestPayload: await _encryptedPayload(runId),
          retryCount: retryCount,
          nextAttemptAt: DateTime.now().toUtc(),
        );
        await _pendingRunQueue.enqueue(payloadRecord);
      }
      rethrow;
    }

    // Attempt upload
    try {
      await _uploader.upload(request);
      await _secureRunSessionManager.markRunUploaded(runId);
      await _pendingRunQueue.deleteByRunId(runId);
    } catch (error) {
      // Upload failed: queue for retry with exponential backoff
      final existingRecord = await _pendingRunQueue.readByRunId(runId);

      if (existingRecord == null) {
        // First failure: enqueue with retryCount=0
        await _pendingRunQueue.enqueue(
          PendingRunRecord(
            runId: runId,
            requestPayload: await _encryptedPayload(runId),
            retryCount: 0,
            nextAttemptAt: DateTime.now().toUtc(),
          ),
        );
      } else {
        // Existing record: check if we've reached max retries
        if (existingRecord.retryCount >= 2) {
          // Next retry would exceed max (retryCount would become 3)
          // Archive it immediately without updating
          await _pendingRunQueue.markAsArchived(runId);
        } else {
          // Can still retry (retryCount is 0 or 1)
          await _pendingRunQueue.updateRetryCountAndSchedule(runId);
        }
      }
      rethrow;
    }
  }

  Future<String> _encryptedPayload(String runId) async {
    final record = await _secureRunSessionManager.encryptedRecordForRun(runId);
    if (record == null) {
      return '';
    }
    return jsonEncode(record.toJson());
  }

  /// Retries all due runs from the pending queue.
  ///
  /// This method is typically called on app startup to retry any runs
  /// that failed to send in the previous session.
  ///
  /// For archived runs (retryCount >= 3), this provides the last opportunity
  /// to submit before the record is considered permanently failed.
  Future<void> retryDueRuns() async {
    final dueRuns = await _pendingRunQueue.dueRuns();

    for (final record in dueRuns) {
      try {
        await submit(record.runId);
      } catch (_) {
        // Continue with next run even if this one fails
        continue;
      }
    }
  }
}

class InMemoryRunUploader implements SubmitRunUploader {
  final Map<String, RunSubmissionRequest> uploadedRuns =
      <String, RunSubmissionRequest>{};

  @override
  Future<void> upload(RunSubmissionRequest request) async {
    uploadedRuns[request.runId] = request;
  }
}
