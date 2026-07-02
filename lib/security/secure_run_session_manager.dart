import 'package:uuid/uuid.dart';

import '../measurement/position.dart';
import 'encrypted_run_record.dart';
import 'encrypted_run_storage.dart';
import 'location_history_cipher.dart';
import 'run_key_manager.dart';

class SecureRunSessionManager {
  SecureRunSessionManager({
    required this.keyManager,
    required this.storage,
    LocationHistoryCipher? cipher,
    Uuid? uuid,
  }) : _cipher = cipher ?? LocationHistoryCipher(),
       _uuid = uuid ?? const Uuid();

  final RunKeyManager keyManager;
  final EncryptedRunStorage storage;
  final LocationHistoryCipher _cipher;
  final Uuid _uuid;

  String? _activeRunId;

  Future<String> startRun() async {
    final runId = _uuid.v4();
    await keyManager.generateForRun(runId);
    _activeRunId = runId;
    return runId;
  }

  Future<EncryptedRunRecord> stopRunAndStoreEncrypted(
    List<GeoPoint> history,
  ) async {
    final runId = _activeRunId;
    if (runId == null) {
      throw StateError('No active run. Call startRun first.');
    }

    final encrypted = await _cipher.encrypt(
      runId: runId,
      history: history,
      keyManager: keyManager,
    );
    await storage.save(encrypted);
    _activeRunId = null;
    return encrypted;
  }

  Future<List<GeoPoint>> decryptForSend(String runId) async {
    final encrypted = await storage.readByRunId(runId);
    if (encrypted == null) {
      throw StateError('No encrypted record for run: $runId');
    }
    return _cipher.decrypt(record: encrypted, keyManager: keyManager);
  }

  Future<void> markRunUploaded(String runId) async {
    await storage.deleteByRunId(runId);
    await keyManager.deleteForRun(runId);
    if (_activeRunId == runId) {
      _activeRunId = null;
    }
  }
}
