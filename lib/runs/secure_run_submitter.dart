import 'dart:convert';

import 'pending_run_queue.dart';
import 'run_submission_request.dart';
import 'submit_run_http_uploader.dart';
import '../security/secure_run_session_manager.dart';

class SecureRunSubmitter {
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

  Future<void> submit(String runId) async {
    final history = await _secureRunSessionManager.decryptForSend(runId);
    final request = _requestFactory.create(
      runId: runId,
      locationHistory: history,
    );

    try {
      await _uploader.upload(request);
      await _secureRunSessionManager.markRunUploaded(runId);
      await _pendingRunQueue.deleteByRunId(runId);
    } catch (error) {
      await _pendingRunQueue.enqueue(
        PendingRunRecord(
          runId: runId,
          requestPayload: jsonEncode(request.toJson()),
          retryCount: 0,
          nextAttemptAt: DateTime.now().toUtc(),
        ),
      );
      rethrow;
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
