import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../measurement/position.dart';
import 'encrypted_run_record.dart';
import 'run_key_manager.dart';

class LocationHistoryCipher {
  LocationHistoryCipher({Cipher? cipher})
    : _cipher = cipher ?? AesGcm.with256bits();

  final Cipher _cipher;

  Future<EncryptedRunRecord> encrypt({
    required String runId,
    required List<GeoPoint> history,
    required RunKeyManager keyManager,
  }) async {
    final secretKey = await keyManager.getForRun(runId);
    final payload = utf8.encode(jsonEncode(_toJson(history)));
    final secretBox = await _cipher.encrypt(payload, secretKey: secretKey);

    return EncryptedRunRecord(
      runId: runId,
      nonceBase64: base64Encode(secretBox.nonce),
      ciphertextBase64: base64Encode(secretBox.cipherText),
      macBase64: base64Encode(secretBox.mac.bytes),
      createdAt: DateTime.now().toUtc(),
    );
  }

  Future<List<GeoPoint>> decrypt({
    required EncryptedRunRecord record,
    required RunKeyManager keyManager,
  }) async {
    final secretKey = await keyManager.getForRun(record.runId);
    final box = SecretBox(
      base64Decode(record.ciphertextBase64),
      nonce: base64Decode(record.nonceBase64),
      mac: Mac(base64Decode(record.macBase64)),
    );

    final clear = await _cipher.decrypt(box, secretKey: secretKey);
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! List) {
      throw StateError('Decrypted payload is not a list');
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(_fromJson)
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _toJson(List<GeoPoint> history) {
    return history
        .map(
          (point) => <String, dynamic>{
            'lat': point.latitude,
            'lng': point.longitude,
            'ts': point.timestamp.toUtc().toIso8601String(),
          },
        )
        .toList(growable: false);
  }

  GeoPoint _fromJson(Map<String, dynamic> json) {
    return GeoPoint(
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      timestamp: DateTime.parse(json['ts'] as String).toUtc(),
    );
  }
}
