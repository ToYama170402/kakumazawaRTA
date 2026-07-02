import 'package:flutter_test/flutter_test.dart';

import 'package:hoge/measurement/position.dart';
import 'package:hoge/runs/pending_run_queue.dart';
import 'package:hoge/runs/run_submission_request.dart';
import 'package:hoge/runs/secure_run_submitter.dart';
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
}
