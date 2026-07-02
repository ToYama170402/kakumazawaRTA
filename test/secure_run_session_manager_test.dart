import 'package:flutter_test/flutter_test.dart';

import 'package:hoge/measurement/position.dart';
import 'package:hoge/security/encrypted_run_storage.dart';
import 'package:hoge/security/run_key_manager.dart';
import 'package:hoge/security/secure_run_session_manager.dart';

void main() {
  test('start -> encrypt store -> decrypt -> cleanup works', () async {
    final manager = SecureRunSessionManager(
      keyManager: InMemoryRunKeyManager(),
      storage: MemoryEncryptedRunStorage(),
    );

    final runId = await manager.startRun();
    final history = <GeoPoint>[
      GeoPoint(
        latitude: 36.545,
        longitude: 136.705,
        timestamp: DateTime.utc(2026, 6, 30, 12, 0, 0),
      ),
      GeoPoint(
        latitude: 36.546,
        longitude: 136.706,
        timestamp: DateTime.utc(2026, 6, 30, 12, 0, 1),
      ),
    ];

    final encrypted = await manager.stopRunAndStoreEncrypted(history);
    expect(encrypted.runId, runId);
    expect(encrypted.ciphertextBase64, isNotEmpty);

    final decrypted = await manager.decryptForSend(runId);
    expect(decrypted.length, 2);
    expect(decrypted.first.latitude, closeTo(36.545, 1e-9));
    expect(decrypted.last.longitude, closeTo(136.706, 1e-9));
    expect(decrypted.first.timestamp, DateTime.utc(2026, 6, 30, 12, 0, 0));

    await manager.markRunUploaded(runId);

    expect(() => manager.decryptForSend(runId), throwsStateError);
  });

  test('stopRunAndStoreEncrypted throws without startRun', () async {
    final manager = SecureRunSessionManager(
      keyManager: InMemoryRunKeyManager(),
      storage: MemoryEncryptedRunStorage(),
    );

    final history = <GeoPoint>[
      GeoPoint(
        latitude: 36.545,
        longitude: 136.705,
        timestamp: DateTime.utc(2026, 6, 30, 12, 0, 0),
      ),
    ];

    expect(() => manager.stopRunAndStoreEncrypted(history), throwsStateError);
  });
}
